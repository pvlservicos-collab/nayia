-- 0127 -- UM FUNIL POR NÚMERO (Pedro, 29/09/2026): "vai ter uma pipeline para
-- cada número, podendo serem alteradas por abas lá em cima, cada tag é uma
-- etapa da pipeline e o lead é movido pelo CRM conforme muda de tag
-- automaticamente". Decisões dele no mesmo dia:
--   * Oficial: o funil que era dividido com a captação ("WhatsApp API
--     (captação)") vira o da Oficial, com as mesmas 4 etapas;
--   * Parceria: as etapas da Nay na frente das da equipe -- Identificação >
--     Recebeu imóvel > Agendamento de visita > Agendou visita > Follow up >
--     Fechou contrato;
--   * Captação: funil novo -- Não respondeu > Respondeu > Disponível > Alugado
--     > Vendido > Mandou os dados (todos que receberam o disparo).
-- `settings.linha` diz de qual número é cada funil. Idempotente.
-- O movimento automático é do CRM (src/lib/funis.ts, cron de minuto).

BEGIN;
SET LOCAL lock_timeout = '5s';

-- a Oficial fica com o funil que era dividido
UPDATE pipelines
   SET name = 'WhatsApp API Oficial',
       settings = coalesce(settings, '{}'::jsonb) || '{"linha": "oficial"}'::jsonb,
       updated_at = now()
 WHERE name = 'WhatsApp API (captação)' AND deleted_at IS NULL;

UPDATE pipelines
   SET settings = coalesce(settings, '{}'::jsonb) || '{"linha": "parceria"}'::jsonb, updated_at = now()
 WHERE name = 'WhatsApp Parceria' AND deleted_at IS NULL AND coalesce(settings->>'linha', '') = '';

-- Parceria: as etapas da Nay na frente
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT id, organization_id FROM pipelines WHERE name = 'WhatsApp Parceria' AND deleted_at IS NULL LOOP
    IF NOT EXISTS (SELECT 1 FROM pipeline_stages WHERE pipeline_id = p.id AND name = 'Identificação' AND deleted_at IS NULL) THEN
      UPDATE pipeline_stages SET rank = rank + 3, updated_at = now() WHERE pipeline_id = p.id AND deleted_at IS NULL;
      INSERT INTO pipeline_stages (id, organization_id, pipeline_id, name, color, rank, created_at, updated_at) VALUES
        (gen_random_uuid(), p.organization_id, p.id, 'Identificação', '#94a3b8', 1, now(), now()),
        (gen_random_uuid(), p.organization_id, p.id, 'Recebeu imóvel', '#0ea5e9', 2, now(), now()),
        (gen_random_uuid(), p.organization_id, p.id, 'Agendamento de visita', '#f97316', 3, now(), now());
    END IF;
  END LOOP;
END $$;

-- Captação: o funil novo, e as etiquetas com os mesmos nomes
DO $$
DECLARE org uuid; pid uuid;
BEGIN
  FOR org IN SELECT DISTINCT organization_id FROM pipelines WHERE name = 'WhatsApp Parceria' AND deleted_at IS NULL LOOP
    SELECT id INTO pid FROM pipelines WHERE organization_id = org AND name = 'WhatsApp Captação' AND deleted_at IS NULL LIMIT 1;
    IF pid IS NULL THEN
      pid := gen_random_uuid();
      INSERT INTO pipelines (id, organization_id, name, settings, created_at, updated_at)
      VALUES (pid, org, 'WhatsApp Captação', '{"linha": "captacao"}'::jsonb, now(), now());
      INSERT INTO pipeline_stages (id, organization_id, pipeline_id, name, color, rank, created_at, updated_at) VALUES
        (gen_random_uuid(), org, pid, 'Não respondeu', '#94a3b8', 1, now(), now()),
        (gen_random_uuid(), org, pid, 'Respondeu', '#0ea5e9', 2, now(), now()),
        (gen_random_uuid(), org, pid, 'Disponível', '#22c55e', 3, now(), now()),
        (gen_random_uuid(), org, pid, 'Alugado', '#f59e0b', 4, now(), now()),
        (gen_random_uuid(), org, pid, 'Vendido', '#ef4444', 5, now(), now()),
        (gen_random_uuid(), org, pid, 'Mandou os dados', '#8b5cf6', 6, now(), now());
    END IF;
    INSERT INTO tags (id, organization_id, name, color, created_at, updated_at)
    SELECT gen_random_uuid(), org, x.nome, x.cor, now(), now()
      FROM (VALUES ('Não respondeu', '#94a3b8'), ('Respondeu', '#0ea5e9'), ('Disponível', '#22c55e'),
                   ('Alugado', '#f59e0b'), ('Vendido', '#ef4444'), ('Mandou os dados', '#8b5cf6'),
                   ('Identificação', '#94a3b8'), ('Recebeu imóvel', '#0ea5e9'), ('Agendamento de visita', '#f97316')) x(nome, cor)
     WHERE NOT EXISTS (SELECT 1 FROM tags t WHERE t.organization_id = org AND t.name = x.nome);
  END LOOP;
END $$;

COMMIT;
