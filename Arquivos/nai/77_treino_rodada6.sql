-- =====================================================================
-- NAI -- 77: rodada de treino 6, so corretor pedindo imovel (Tel, 22/09/2026)
--
-- Ele: "as conversas que foram la foram muito aleatorias, filtra nas
-- conversas que temos na base as conversas de corretores mesmo, pedindo
-- imovel bonitinho, quero 50 dessas". Depois, perguntado: "So os 29 reais".
--
-- O QUE A BASE TEM DE VERDADE: varri as 9.972 mensagens privadas desde 10/08
-- (a tabela `grupo_mensagens` esta vazia -- o que e postado nos grupos nao e
-- guardado). Tirando dono de imovel (`nai_lista_governa`), numeros de teste,
-- card colado, CPF, anuncio, resposta automatica, visita e contrato, sobraram
-- 29. Lidos um a um:
--   8 eram do "Corretor de Teste" (5592988887777) -- os meus testes de 19/09;
--   3 ja tinham virado caso em rodada anterior;
--   7 nao eram pedido: dono falando do proprio imovel ("a chave esta com meu
--     primo", "pagando ate o dia 05 tem desconto") ou negociacao/opiniao;
--   2 vagos demais sem a conversa em volta ("Me passa qual o apto").
-- Ficam os 9 abaixo, escolhidos pelo id da mensagem.
--
-- CINCO DELES NUNCA PASSARAM PELA NAY (ela estava desligada; quem respondeu
-- foi o Tel pelo celular) e nao tem `nai_turno`. `turno_origem` tinha NOT NULL
-- e chave estrangeira para `nai_turno`. Inventar turno falso sujaria os paineis
-- de producao; entao a tabela de TREINO passa a aceitar a MENSAGEM como origem
-- (`msg_origem`), e pelo menos uma das duas tem que existir. So mexe em
-- `nai_treino_caso` -- nada de producao. Quem le `turno_origem` (o pool, a
-- montagem antiga, o painel e o executor) aguenta ele vazio.
-- Esses 5 sao pedidos completos, que se entendem sozinhos.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE nai_treino_caso ALTER COLUMN turno_origem DROP NOT NULL;
ALTER TABLE nai_treino_caso ADD COLUMN IF NOT EXISTS msg_origem integer REFERENCES mensagens(id);
CREATE UNIQUE INDEX IF NOT EXISTS nai_treino_caso_msg_origem_key
  ON nai_treino_caso (msg_origem) WHERE msg_origem IS NOT NULL;
ALTER TABLE nai_treino_caso DROP CONSTRAINT IF EXISTS nai_treino_caso_origem_ok;
ALTER TABLE nai_treino_caso ADD CONSTRAINT nai_treino_caso_origem_ok
  CHECK (turno_origem IS NOT NULL OR msg_origem IS NOT NULL);

WITH ciclo AS (
  INSERT INTO nai_treino_ciclo (rotulo, tamanho) VALUES ('Rodada de treino 6', 9) RETURNING id
),
escolhidas(msg_id) AS (VALUES
  (1509),   -- Solange: "Nay vc tem foto da suite do Grand Prix"
  (5645),   -- Leonardo: "O Acquarelle teria alguma margem para negociar... teto dela e 3200"
  (6136),   -- "Me manda o Castelli as fotos"
  (10186),  -- Rosineide: "Preciso casa mobiliado no parque 10 ate 6mil"
  (12734),  -- Andre: "Manda essa casa do Aleixo"
  (13027),  -- Leonardo: "O Mirante das flores ainda esta disponivel? Tenho um cliente militar"
  (15062),  -- Aira: "Vc tem uma Casa no Morada dos passaros para venda, 900k?"
  (15484),  -- Fiuza: "Ce tem casa em condominio pra aluguel ate 5k semi ou toda mobiliada?"
  (15560)   -- Silvana: "Vc me passa mais informacoes desse conquista Rio Negro?"
),
fonte AS (
  SELECT m.id AS msg_id, m.texto, m.criada_em, c.id AS contato_id,
         (SELECT t.id FROM nai_turno t
           WHERE t.contato_id = c.id
             AND t.texto ILIKE '%' || left(m.texto, 30) || '%'
             AND abs(extract(epoch FROM t.criado_em - m.criada_em)) < 600
           ORDER BY t.id LIMIT 1) AS turno_id
    FROM escolhidas e
    JOIN mensagens m ON m.id = e.msg_id
    JOIN nai_contato c ON c.chave = nai_chave(m.telefone)
)
INSERT INTO nai_treino_caso (
  ciclo_id, turno_origem, msg_origem, contato_origem, papel, quando_original,
  ele_disse, ela_respondeu_antes, ferramentas_antes, contexto)
SELECT (SELECT id FROM ciclo),
       f.turno_id, f.msg_id,
       f.contato_id, 'corretor',
       coalesce((SELECT t.criado_em FROM nai_turno t WHERE t.id = f.turno_id), f.criada_em),
       coalesce((SELECT t.texto FROM nai_turno t WHERE t.id = f.turno_id), f.texto),
       (SELECT string_agg(x.texto, E'\n---\n' ORDER BY x.ordem, x.id)
          FROM nai_saida x WHERE x.turno_id = f.turno_id AND x.tipo = 'texto'),
       coalesce((SELECT t.ferramentas FROM nai_turno t WHERE t.id = f.turno_id), '{}'),
       nai_treino_contexto(f.contato_id,
         coalesce((SELECT t.criado_em FROM nai_turno t WHERE t.id = f.turno_id), f.criada_em), 10)
  FROM fonte f;

UPDATE nai_treino_ciclo c SET tamanho = (SELECT count(*) FROM nai_treino_caso k WHERE k.ciclo_id = c.id)
 WHERE c.rotulo = 'Rodada de treino 6' AND c.fechado_em IS NULL;

COMMIT;

SELECT k.id, k.turno_origem, k.msg_origem, left(regexp_replace(k.ele_disse, '\s+', ' ', 'g'), 70) AS ele_disse,
       jsonb_array_length(k.contexto) AS falas_antes
  FROM nai_treino_caso k JOIN nai_treino_ciclo c ON c.id = k.ciclo_id
 WHERE c.rotulo = 'Rodada de treino 6' ORDER BY k.id;
