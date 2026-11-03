-- 567 (Pedro, 02/11/2026, "pode mover"): 9055, 9057, 9058, 9067 e 9068, do grupo CADASTRO, tinham característica do imóvel na
-- Observação do card (escrita pela equipe no admin, não pela Nay). Pela regra de 02/11 (566) o card leva só o negócio: o texto
-- vai para o fim da Descrição (que não sai no card e a Nay lê para responder) quando ela ainda não o tem, e a Observação fica
-- vazia. O texto de antes está no backup /root/backups-funcoes/observacao-5-do-grupo-2026-11-02.csv.
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE imoveis
   SET descricao = CASE WHEN position(btrim(observacao) IN coalesce(descricao, '')) > 0 THEN descricao
                        ELSE concat_ws(E'\n\n', nullif(btrim(descricao), ''), btrim(observacao)) END,
       observacao = NULL
 WHERE codigo IN (9055, 9057, 9058, 9067, 9068) AND observacao IS NOT NULL;
SELECT codigo, observacao IS NULL AS card_limpo, right(descricao, 90) AS fim_da_descricao
  FROM imoveis WHERE codigo IN (9055, 9057, 9058, 9067, 9068) ORDER BY 1;
COMMIT;
