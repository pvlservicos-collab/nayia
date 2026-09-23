-- =====================================================================
-- NAI -- 73: fecha a rodada 2, abre a rodada 3 (Tel, 21/09/2026)
--
-- Mesma mecanica do 70: os casos MUDAM de ciclo, nao sao copiados
-- (nai_treino_caso tem UNIQUE em turno_origem).
--
-- O que ele julgou na rodada 2 -- o caso 6, a CTA -- ja esta aplicado no 72
-- e por isso fica de fora desta rodada.
--
-- Os dois que deram erro na rodada 2 (4 e 46, PROMPT_VAZIO) VOLTAM: nao sao
-- resposta julgada, sao execucao que nao aconteceu. Com sorte a instabilidade
-- nao repete; se repetir no mesmo caso, ai e sinal de causa e nao de azar.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

UPDATE nai_treino_ciclo SET fechado_em = now() WHERE id = 4 AND fechado_em IS NULL;

INSERT INTO nai_treino_ciclo (rotulo, tamanho)
VALUES ('Rodada de treino 3',
        (SELECT count(*) FROM nai_treino_caso
          WHERE ciclo_id = 4 AND id NOT IN (SELECT caso_id FROM nai_treino_julgamento WHERE aplicada_em IS NOT NULL)));

UPDATE nai_treino_caso SET
  ciclo_id            = (SELECT max(id) FROM nai_treino_ciclo),
  ela_respondeu_antes = ela_respondeu_agora,
  ferramentas_antes   = ferramentas_agora,
  ela_respondeu_agora = NULL,
  ferramentas_agora   = '{}',
  turno_simulado      = NULL,
  exec_id             = NULL,
  erro                = NULL,
  rodado_em           = NULL,
  estado              = 'pendente'
 WHERE ciclo_id = 4
   AND id NOT IN (SELECT caso_id FROM nai_treino_julgamento WHERE aplicada_em IS NOT NULL);

COMMIT;

SELECT id, rotulo, tamanho, coalesce(fechado_em::text,'aberto') AS fechado
  FROM nai_treino_ciclo ORDER BY id;
SELECT ciclo_id, estado, count(*) FROM nai_treino_caso GROUP BY 1,2 ORDER BY 1,2;
