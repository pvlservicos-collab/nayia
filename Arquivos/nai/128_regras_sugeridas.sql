-- =====================================================================
-- 128 — REGRAS SUGERIDAS (27/09/2026)
--
-- Tel: "crie uma nova função la no site treino da nay, eu vou pedir umas
-- janelas de conversa, vc vai analisar todas as regras de hoje, e ver as
-- conversas para ver o que a nay não entenderia hoje... e vai me sugerir
-- regras novas... ao clicar na regra aparece um popup com a conversa que ela
-- veio".
--
-- DUAS TABELAS, e a razão é a segunda:
--
--   nai_regra_sugerida       -- a regra proposta
--   nai_regra_sugerida_caso  -- as conversas que a provam, uma linha cada
--
-- Uma sugestão nasce de VÁRIAS conversas. "Nove corretores pediram para entrar
-- no grupo de alto padrão numa semana" é um argumento; "um corretor pediu" é
-- um caso isolado. Guardar os casos em linha separada é o que deixa o popup
-- mostrar todos e o número de ocorrências ser contado, não digitado.
--
-- `estado` fecha o ciclo: sugerida -> aceita (virou regra em `nai_regra`) ou
-- recusada. Sem isso a lista viraria um monte de sugestão repetida a cada
-- rodada, e ninguém confia numa lista que não lembra o que já foi decidido.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS nai_regra_sugerida (
  id           bigserial PRIMARY KEY,
  rodada       integer NOT NULL DEFAULT 1,
  criada_em    timestamptz NOT NULL DEFAULT now(),
  -- a janela de conversa que foi lida para chegar nesta sugestão
  janela_de    date,
  janela_ate   date,
  -- como ele pediu: classificada por categoria e por importância
  categoria    text NOT NULL,
  importancia  text NOT NULL DEFAULT 'media'
               CHECK (importancia IN ('alta', 'media', 'baixa')),
  titulo       text NOT NULL,
  -- a regra escrita do jeito que entraria em `nai_regra`
  regra        text NOT NULL,
  o_que_faz    text,
  -- por que eu sugeri: o que ela fez ou deixou de fazer
  porque       text NOT NULL,
  -- o tipo que ela teria em `nai_regra`, se aceita
  tipo         text NOT NULL DEFAULT 'fluxo'
               CHECK (tipo IN ('parede', 'fluxo', 'ajuste', 'defeito')),
  estado       text NOT NULL DEFAULT 'sugerida'
               CHECK (estado IN ('sugerida', 'aceita', 'recusada')),
  decidido_em  timestamptz,
  decidido_por text,
  nota_do_tel  text
);

CREATE TABLE IF NOT EXISTS nai_regra_sugerida_caso (
  id          bigserial PRIMARY KEY,
  sugestao_id bigint NOT NULL REFERENCES nai_regra_sugerida(id) ON DELETE CASCADE,
  quem        text,
  chave       text,
  quando      timestamptz,
  turno_id    bigint,
  ele_disse   text,
  ela_disse   text,
  -- o que esta conversa prova em uma linha, para o popup não obrigar a ler tudo
  o_ponto     text
);

CREATE INDEX IF NOT EXISTS nai_regra_sugerida_caso_da_sugestao
  ON nai_regra_sugerida_caso (sugestao_id, quando);
CREATE INDEX IF NOT EXISTS nai_regra_sugerida_por_estado
  ON nai_regra_sugerida (estado, importancia, rodada);

COMMIT;

\echo '=== as duas tabelas ==='
SELECT tablename FROM pg_tables WHERE tablename LIKE 'nai_regra_sugerida%' ORDER BY 1;
