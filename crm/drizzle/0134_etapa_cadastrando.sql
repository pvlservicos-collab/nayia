-- 0134 -- A ETAPA CADASTRANDO (Pedro, 20/10/2026: "será criada uma nova etapa lá no CRM, no final: Cadastrando").
-- A última coluna do funil da Parceria. Quem está nela é quem a Nay do cadastro está perguntando sobre um imóvel
-- (nayia 428/431: crm_parceria_funil devolve 'Cadastrando'); src/lib/funis.ts põe o card aqui e devolve para a etapa
-- de antes quando o cadastro acaba. A etiqueta de mesmo nome nasce sozinha (o espelho de etiquetas do funis.ts).
-- Idempotente.
BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO pipeline_stages (id, organization_id, pipeline_id, name, nome_original, color, rank, created_at, updated_at)
SELECT gen_random_uuid(), p.organization_id, p.id, 'Cadastrando', 'Cadastrando', '#14b8a6',
       coalesce((SELECT max(s.rank) FROM pipeline_stages s WHERE s.pipeline_id = p.id AND s.deleted_at IS NULL), 0) + 1,
       now(), now()
  FROM pipelines p
 WHERE p.name = 'WhatsApp Parceria' AND p.deleted_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM pipeline_stages s WHERE s.pipeline_id = p.id AND s.deleted_at IS NULL
                     AND (s.name = 'Cadastrando' OR s.nome_original = 'Cadastrando'));

SELECT s.name, s.rank FROM pipeline_stages s JOIN pipelines p ON p.id = s.pipeline_id
 WHERE p.name = 'WhatsApp Parceria' AND s.deleted_at IS NULL AND p.deleted_at IS NULL ORDER BY s.rank;
COMMIT;
