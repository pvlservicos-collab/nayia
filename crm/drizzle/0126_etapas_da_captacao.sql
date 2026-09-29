-- =====================================================================
-- 0126 — AS ETAPAS DA CAPTAÇÃO (28/09/2026)
--
-- Tel (pelo Pedro): "põe assim as pipelines:
--   - Recebeu mensagem
--   - Em atendimento
--   - Atualizou cadastro do seu imóvel
--   - Sugeriu outro imóvel"
--
-- Vale para o pipeline "WhatsApp API (captação)", o das abas Oficial e
-- Captação (os proprietários da campanha). O da Parceria (corretores) não muda.
--
-- As etiquetas do chat têm os MESMOS nomes das etapas, de propósito: marcar a
-- etiqueta move o card (ver api/leads/[id]/tags). Então elas mudam junto:
--   Contactando  -> Recebeu mensagem
--   Follow up    -> Em atendimento        (a ETIQUETA "Follow up" fica: a Parceria usa)
--   Imóvel novo  -> Atualizou cadastro do seu imóvel
--   (nova)       -> Sugeriu outro imóvel
--
-- Nenhum lead estava nessas etapas nem com essas etiquetas (conferido às
-- 17:50); a conferência abaixo para tudo se isso tiver mudado.
--
-- ATENÇÃO: "Em atendimento" só pode existir com o CRM que procura essa etapa
-- DENTRO do pipeline do lead (etapaEmAtendimentoDoMesmoPipeline, 28/09). O
-- código velho a procurava na organização inteira e jogaria qualquer conversa
-- respondida no funil da captação.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM leads
              WHERE deleted_at IS NULL
                AND stage_id IN ('35484c85-a7e3-4221-9618-b0d625cfb1c9',
                                 'b4536a98-dbb3-4d16-918d-9c8a247bcb88',
                                 '5c390ab6-8f0b-4dbb-8117-1926a16ecea6')) THEN
    RAISE EXCEPTION 'tem lead nas etapas antigas da captação -- nada gravado';
  END IF;
  IF EXISTS (SELECT 1 FROM lead_tags
              WHERE tag_id IN ('af7dd6ea-b4b2-40ee-8ce4-0e93a6e53e31',
                               '064ed431-cb9e-4427-a106-3046634d7753')) THEN
    RAISE EXCEPTION 'tem lead com as etiquetas Contactando/Imóvel novo -- nada gravado';
  END IF;
END $$;

-- as etapas (mesmos ids: o que já aponta para elas continua valendo)
UPDATE pipeline_stages SET name = 'Recebeu mensagem', updated_at = now()
 WHERE id = '35484c85-a7e3-4221-9618-b0d625cfb1c9' AND name = 'Contactando';
UPDATE pipeline_stages SET name = 'Em atendimento', updated_at = now()
 WHERE id = 'b4536a98-dbb3-4d16-918d-9c8a247bcb88' AND name = 'Follow up';
UPDATE pipeline_stages SET name = 'Atualizou cadastro do seu imóvel', updated_at = now()
 WHERE id = '5c390ab6-8f0b-4dbb-8117-1926a16ecea6' AND name = 'Imóvel novo';

INSERT INTO pipeline_stages (id, organization_id, pipeline_id, name, color, rank, created_at, updated_at)
SELECT gen_random_uuid(), s.organization_id, s.pipeline_id, 'Sugeriu outro imóvel', '#14b8a6', 4, now(), now()
  FROM pipeline_stages s
 WHERE s.id = '5c390ab6-8f0b-4dbb-8117-1926a16ecea6'
   AND NOT EXISTS (SELECT 1 FROM pipeline_stages x
                    WHERE x.pipeline_id = s.pipeline_id AND x.deleted_at IS NULL
                      AND x.name = 'Sugeriu outro imóvel');

-- as etiquetas do chat, com os mesmos nomes e as mesmas cores
UPDATE tags SET name = 'Recebeu mensagem', updated_at = now()
 WHERE id = 'af7dd6ea-b4b2-40ee-8ce4-0e93a6e53e31' AND name = 'Contactando';
UPDATE tags SET name = 'Atualizou cadastro do seu imóvel', updated_at = now()
 WHERE id = '064ed431-cb9e-4427-a106-3046634d7753' AND name = 'Imóvel novo';

INSERT INTO tags (id, organization_id, name, color, created_at, updated_at)
SELECT gen_random_uuid(), t.organization_id, novo.nome, novo.cor, now(), now()
  FROM tags t
 CROSS JOIN (VALUES ('Em atendimento', '#f59e0b'), ('Sugeriu outro imóvel', '#14b8a6')) AS novo(nome, cor)
 WHERE t.id = 'af7dd6ea-b4b2-40ee-8ce4-0e93a6e53e31'
   AND NOT EXISTS (SELECT 1 FROM tags x WHERE x.organization_id = t.organization_id AND x.name = novo.nome);

-- como ficou
SELECT p.name AS pipeline, s.rank, s.name AS etapa, s.color
  FROM pipeline_stages s JOIN pipelines p ON p.id = s.pipeline_id
 WHERE p.deleted_at IS NULL AND s.deleted_at IS NULL
 ORDER BY p.name, s.rank;

SELECT name AS etiqueta, color
  FROM tags
 WHERE name IN ('Recebeu mensagem', 'Em atendimento', 'Atualizou cadastro do seu imóvel',
                'Sugeriu outro imóvel', 'Follow up', 'Agendou visita', 'Fechou contrato')
 ORDER BY name;

COMMIT;
