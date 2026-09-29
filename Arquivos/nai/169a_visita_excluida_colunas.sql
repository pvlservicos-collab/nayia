-- 169a -- a visita excluída pelo CRM (29/09/2026). Só o esquema, curto e com
-- trava de 5 s (ver memória `ensaio-sem-ddl-no-banco-vivo`): coluna nova sem
-- valor padrão é só metadado, não reescreve a tabela.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE nai_visita
  ADD COLUMN IF NOT EXISTS excluida_em timestamptz,
  ADD COLUMN IF NOT EXISTS excluida_por text;
COMMENT ON COLUMN nai_visita.excluida_em IS
  'Excluída no CRM (Visitas agendadas): some da agenda e das telas; ninguém é avisado. Ver 169.';
COMMIT;
