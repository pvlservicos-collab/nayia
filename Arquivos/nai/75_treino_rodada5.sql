-- =====================================================================
-- NAI -- 75: rodada de treino 5, com as conversas da SEMANA (Tel, 21/09/2026)
--
-- Ele: "que sejam outras conversas do nosso banco de mais de 300 conversas
-- da semana, quero testar outras 50 com o modelo atual, conversa por
-- conversa".
--
-- POR QUE NAO USEI O `nai_treino_montar_ciclo` DE SEMPRE:
-- ele tira do `nai_treino_pool`, que so aceita fala que a Nay RESPONDEU na
-- epoca -- era para comparar o antes e o depois. Com ela desligada quase a
-- semana toda, sobraram 274 falas de so 7 corretores; as 50 mais novas eram
-- de 4 pessoas. Ou seja: a mesma conversa repetida doze vezes.
-- Ele ja disse que nao quer mais o antes/depois ("n precisa por antes e
-- depois"). Entao a exigencia caiu, e a fonte passa a ser toda fala de
-- corretor da semana: 745 falas de 114 pessoas.
--
-- COMO ESCOLHE:
--   * so corretor, so dos ultimos 7 dias, fala com pelo menos 12 letras
--     ("ok", "bom dia" sozinhos nao testam nada);
--   * PESSOA NOVA: ninguem que ja apareceu em rodada anterior;
--   * UMA fala por pessoa -- a mais recente dela -- para serem 50 conversas
--     de verdade, e nao 50 mensagens de meia duzia;
--   * fora o espelho do treino, os numeros de teste e os de comando.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

WITH ciclo AS (
  INSERT INTO nai_treino_ciclo (rotulo, tamanho)
  VALUES ('Rodada de treino 5', 50)
  RETURNING id
),
excluidos AS (
  SELECT nai_chave(btrim(x)) AS chave
    FROM regexp_split_to_table(nai_cfg('numeros_teste', '') || ',' ||
                               nai_cfg('comando_telefones', '') || ',' ||
                               nai_cfg('treino_espelho', ''), ',') x
   WHERE btrim(x) <> ''
),
uma_por_pessoa AS (
  SELECT DISTINCT ON (t.contato_id)
         t.id, t.contato_id, t.papel, t.criado_em, t.texto, t.ferramentas
    FROM nai_turno t
    JOIN nai_contato c ON c.id = t.contato_id
   WHERE t.papel = 'corretor'
     AND t.criado_em > now() - interval '7 days'
     AND length(btrim(coalesce(t.texto, ''))) >= 12
     AND c.chave IS NOT NULL
     AND c.chave NOT IN (SELECT chave FROM excluidos WHERE chave IS NOT NULL)
     AND NOT EXISTS (SELECT 1 FROM nai_treino_caso k
                      WHERE k.turno_origem = t.id OR k.turno_simulado = t.id
                         OR k.contato_origem = t.contato_id)
   ORDER BY t.contato_id, t.criado_em DESC
)
INSERT INTO nai_treino_caso (
  ciclo_id, turno_origem, contato_origem, papel, quando_original,
  ele_disse, ela_respondeu_antes, ferramentas_antes, contexto)
SELECT (SELECT id FROM ciclo), p.id, p.contato_id, p.papel, p.criado_em,
       p.texto,
       (SELECT string_agg(x.texto, E'\n---\n' ORDER BY x.ordem, x.id)
          FROM nai_saida x WHERE x.turno_id = p.id AND x.tipo = 'texto'),
       coalesce(p.ferramentas, '{}'),
       nai_treino_contexto(p.contato_id, p.criado_em, 10)
  FROM (SELECT * FROM uma_por_pessoa ORDER BY criado_em DESC LIMIT 50) p;

-- o tamanho real, caso sobrem menos de 50 pessoas
UPDATE nai_treino_ciclo c SET tamanho = (SELECT count(*) FROM nai_treino_caso k WHERE k.ciclo_id = c.id)
 WHERE c.rotulo = 'Rodada de treino 5' AND c.fechado_em IS NULL;

COMMIT;

SELECT c.id, c.rotulo, c.tamanho,
       count(DISTINCT k.contato_origem)    AS pessoas,
       min(k.quando_original)::date        AS de,
       max(k.quando_original)::date        AS ate
  FROM nai_treino_ciclo c JOIN nai_treino_caso k ON k.ciclo_id = c.id
 WHERE c.rotulo = 'Rodada de treino 5'
 GROUP BY 1, 2, 3;
