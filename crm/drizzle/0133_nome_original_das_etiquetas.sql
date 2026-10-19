-- 0133 -- RENOMEAR ETIQUETA (Pedro, 19/10/2026: "coloca para eu poder editar o nome de todas as tags").
-- A etiqueta e a etapa do funil de mesmo nome são uma coisa só (api/leads/[id]/tags) e o funil automático
-- (src/lib/funis.ts), a etapa "Em atendimento" (etapaDaLinha.ts) e o Orgânico (tagOrganico.ts) acham pelo nome.
-- Renomear troca o nome da etiqueta E da etapa de mesmo nome, e guarda aqui o nome de nascença (só a primeira
-- vez): o código procura pelo nome OU pelo nome_original, e nada para de funcionar.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL ROLE crm;
ALTER TABLE tags ADD COLUMN IF NOT EXISTS nome_original text;
ALTER TABLE pipeline_stages ADD COLUMN IF NOT EXISTS nome_original text;
COMMIT;
