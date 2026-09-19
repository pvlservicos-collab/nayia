-- Prova a parede do código, e prova que ela não fecha demais.
--
-- O CASO que ela veio impedir (01/09, 00h21): o modelo passou
-- `codigo: "5717"` numa pergunta sobre o imóvel 4946, tirando o número da
-- memória de conversa. `nay_escalar` aceitou, e a resposta do Tel iria
-- para `pendencias.resposta` amarrada ao imóvel errado, reusada nele para
-- sempre.
--
-- Roda dentro de BEGIN/ROLLBACK e monta o cenário do zero, então não
-- depende do que estiver no banco no momento.
--
--   docker cp teste_codigo_confirmado.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

-- Um corretor de teste, com telefone que não colide com ninguém real.
INSERT INTO corretores (telefone, nome, aprovado, ativo)
VALUES ('5592900000001', 'Corretor de Teste', true, true)
ON CONFLICT DO NOTHING;

-- Ele escreveu o 4946. Nunca escreveu o 5717.
INSERT INTO mensagens (telefone, direcao, origem, texto, status)
VALUES ('5592900000001', 'recebida', 'texto', 'me fala do 4946', 'Recebido');

-- E ele disse um VALOR que também é um código existente.
INSERT INTO mensagens (telefone, direcao, origem, texto, status)
VALUES ('5592900000001', 'recebida', 'texto', 'o cliente paga até 4000', 'Recebido');

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

INSERT INTO resultado VALUES
  ('código que ELE escreveu',
   nay_codigo_confirmado('5592900000001','4946'), 'dito_por_ele'),
  ('código que o MODELO inventou',
   nay_codigo_confirmado('5592900000001','5717'), 'nao'),
  ('valor que parece código ("paga até 4000")',
   nay_codigo_confirmado('5592900000001','4000'), 'nao'),
  ('telefone com 13 dígitos, mesmo corretor',
   nay_codigo_confirmado('55929000000001','4946'), 'dito_por_ele'),
  ('telefone de outro corretor',
   nay_codigo_confirmado('5592911111111','4946'), 'nao'),
  ('código vazio',
   nay_codigo_confirmado('5592900000001',''), 'nao'),
  ('código nulo',
   nay_codigo_confirmado('5592900000001',NULL), 'nao');

-- E o card único que a Nay mandou, que também confirma.
INSERT INTO envios (codigo, telefone, destino)
VALUES ('3471', '5592900000001', 'corretor');

INSERT INTO resultado VALUES
  ('card único que ELA mandou',
   nay_codigo_confirmado('5592900000001','3471'), 'unico_card');

-- Com DOIS cards, "esse" volta a ser ambíguo e nenhum dos dois confirma.
INSERT INTO envios (codigo, telefone, destino)
VALUES ('3495', '5592900000001', 'corretor');

INSERT INTO resultado VALUES
  ('com dois cards mandados, nenhum confirma sozinho',
   nay_codigo_confirmado('5592900000001','3471'), 'nao');

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

-- --------------------------------------------------------------------
-- E o que o `nay_escalar` faz com cada um deles.
SELECT 'escalar com código inventado -> ' || acao AS r
  FROM nay_escalar('5592900000001','Teste','5717','quitação','esse tá quitado?');

SELECT 'escalar com código que ele disse -> ' || acao AS r
  FROM nay_escalar('5592900000001','Teste','4946','aceita pet','o 4946 aceita pet?');

SELECT 'escalar pedindo o apartamento -> ' || acao AS r
  FROM nay_escalar('5592900000001','Teste','4946','andar bloco apto','qual andar, bloco e apartamento');

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
