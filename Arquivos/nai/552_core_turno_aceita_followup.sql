-- 552 (31/10/2026): o follow-up de visita da Parceria (nay-core 0cfbc09, 21/10: "a confirmação sem resposta" em 30 min
-- e "E aí, seu cliente confirmou?" em 1 h) grava o turno com caminho = 'followup', e a restrição de core_turno só
-- aceitava pre_roteador/classificador/fallback/fora_do_escopo. A transação inteira era desfeita (core_followup vazia):
-- desde 21/10 nenhum desses follow-ups saiu. Achado no log do worker depois do deploy da revisão de 30/10.
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE public.core_turno DROP CONSTRAINT core_turno_caminho_check;
ALTER TABLE public.core_turno ADD CONSTRAINT core_turno_caminho_check
  CHECK (caminho = ANY (ARRAY['pre_roteador', 'classificador', 'fallback', 'fora_do_escopo', 'followup'])) NOT VALID;
ALTER TABLE public.core_turno VALIDATE CONSTRAINT core_turno_caminho_check;
COMMIT;
