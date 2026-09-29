-- =====================================================================
-- 136 — A NAY VOLTA PARA TODOS OS CORRETORES ÀS 7H, SEM FILA (28/09/2026)
--
-- Pedido: "você pode ligar a nay amanhã às 7 mas sem fila" (mensagem da noite
-- de 27/09 -> segunda, 28/09, 07:00 de Manaus). Roda por cron, uma vez só
-- (/root/ligar_nay_20260928.sh, 11:00 UTC).
--
-- "LIGAR" = tirar a lista curta (desde 25/09 ela só respondia Pedro, Tel e
-- Rayssa). O resto já está no ar: modo=todos, regra_publico=sim, só corretor
-- da lista (grupos + Xx).
--
-- "SEM FILA" = ela não responde o que acumulou enquanto estava fechada:
--   * o carimbo `regra_publico_desde` vira AGORA: conversa com mensagem antes
--     dele é do Tel, e ela só entra se a pessoa pedir foto de um imóvel ou
--     pedir imóveis -- o mesmo desenho da religação de 22/09 (84);
--   * `liberado_em` volta a zero (guardado antes), senão quem foi liberado na
--     semana voltaria direto para ela;
--   * o que estiver pendente na caixa de saída há mais de 10 minutos não sai.
--
-- A EQUIPE CONTINUA EQUIPE: o Pedro entrou em `equipe` (28/09, 00h) porque,
-- sem a lista curta, ele deixaria de contar como equipe -- e perderia o
-- comando de envio (135) e a isenção da janela (130).
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS nai_backup_religar_20260928 AS
  SELECT id, chave, liberado_em, liberado_motivo, now() AS guardado_em
    FROM nai_contato WHERE liberado_em IS NOT NULL;
CREATE TABLE IF NOT EXISTS nai_backup_config_20260928 AS
  SELECT chave, valor, now() AS guardado_em FROM nai_config
   WHERE chave IN ('so_estes_numeros', 'regra_publico_desde', 'modo', 'pausada',
                   'envio_simulado', 'regra_publico', 'so_corretor_da_lista');

UPDATE nai_contato SET liberado_em = NULL, liberado_motivo = NULL
 WHERE liberado_em IS NOT NULL
   AND NOT (chave = ANY (nai_chaves_teste()))
   AND NOT nai_e_da_equipe_contato(id);

UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'fila antiga: religada 28/09 07:00 sem fila'
 WHERE estado = 'pendente' AND criado_em < now() - interval '10 minutes';

UPDATE nai_config SET valor = '', atualizado_em = now() WHERE chave = 'so_estes_numeros';
UPDATE nai_config SET valor = to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF'), atualizado_em = now()
 WHERE chave = 'regra_publico_desde';

COMMIT;

SELECT chave, valor FROM nai_config
 WHERE chave IN ('modo', 'pausada', 'envio_simulado', 'regra_publico', 'regra_publico_desde',
                 'so_estes_numeros', 'so_corretor_da_lista', 'proprietario_pelo_tel')
 ORDER BY 1;
