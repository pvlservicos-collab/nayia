-- =====================================================================
-- NAI -- 70: fecha o ciclo 1, guarda o que ja foi visto, abre o ciclo 2
--
-- Tel (21/09): "pode por essas conversas em um banco de ja utilizadas e ai
-- depois dessas regras ja implementadas, roda novamente as outras conversas
-- fora as que ja vi com essa nova nay ja corrigida".
--
-- "Ja utilizadas" nao virou tabela nova: virou a coluna `aplicada_em` do
-- julgamento, que ja existia para isto, mais o fechamento do ciclo 1. Tabela
-- nova seria um segundo lugar para a mesma verdade.
--
-- O QUE FOI APLICADO DE CADA CASO:
--   caso 1  NADA NA NAY -- era falso positivo. Ela resolve a citacao certo
--           (nay_imovel_da_citacao devolve 4262, e o turno original tinha
--           esse imovel em foco). Quem errava era o SIMULADOR, que nao
--           mandava referenceMessageId. Consertado em nai_treino_rodar.py.
--   caso 2  Metade: "o card vai inteiro" entrou no prompt (69). A outra
--           metade -- o valor do condominio do 5727 -- NAO TEM CONSERTO:
--           o dado nao existe no banco, nao esta no anuncio do site, e
--           taxa_condominio nem esta na lista que a varredura traz.
--   caso 3  "as fotos vao junto, sem perguntar", no prompt (69).
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1. Os tres casos ficam marcados como ja aplicados -- nao voltam na rodada 2.
UPDATE nai_treino_julgamento SET
  aplicada_em = now(),
  aplicada_como = CASE caso_id
    WHEN 1 THEN 'simulador: nai_treino_rodar.py passou a mandar referenceMessageId. A Nay nao mudou -- ela ja acertava.'
    WHEN 2 THEN '69_card_e_fotos: regra "o card vai inteiro". A taxa de condominio do 5727 nao existe em lugar nenhum: sem conserto.'
    WHEN 3 THEN '69_card_e_fotos: regra "as fotos vao junto, sem perguntar" (a regra de perguntar era do 68, de 20/09).'
  END
 WHERE caso_id IN (1, 2, 3) AND aplicada_em IS NULL;

-- 2. O ciclo 1 fecha.
UPDATE nai_treino_ciclo SET fechado_em = now() WHERE id = 1 AND fechado_em IS NULL;

-- 3. O ciclo 2.
--
-- `nai_treino_caso` tem UNIQUE em turno_origem: um caso existe UMA vez, nao
-- um por ciclo. Entao nao se copia -- se MOVE. Os 46 que ele ainda nao viu
-- passam para o ciclo novo, e a resposta da rodada 1 vira o "antes" da 2,
-- que e contra o que a comparacao faz sentido agora.
INSERT INTO nai_treino_ciclo (rotulo, tamanho)
VALUES ('Rodada de treino 2',
        (SELECT count(*) FROM nai_treino_caso WHERE ciclo_id = 1 AND id NOT IN (1,2,3)));

UPDATE nai_treino_caso SET
  ciclo_id            = (SELECT max(id) FROM nai_treino_ciclo),
  ela_respondeu_antes = ela_respondeu_agora,
  ferramentas_antes   = ferramentas_agora,
  ela_respondeu_agora = NULL,
  ferramentas_agora   = '{}',   -- NOT NULL: array vazio, nao NULL
  turno_simulado      = NULL,
  exec_id             = NULL,
  erro                = NULL,
  rodado_em           = NULL,
  estado              = 'pendente'
 WHERE ciclo_id = 1 AND id NOT IN (1, 2, 3);

COMMIT;

SELECT id, rotulo, tamanho,
       criado_em AT TIME ZONE 'America/Manaus' AS criado,
       coalesce(fechado_em::text, 'aberto') AS fechado
  FROM nai_treino_ciclo ORDER BY id;

SELECT ciclo_id, estado, count(*) FROM nai_treino_caso GROUP BY 1,2 ORDER BY 1,2;

SELECT caso_id, veredito, left(aplicada_como, 62) AS aplicada_como
  FROM nai_treino_julgamento ORDER BY caso_id;
