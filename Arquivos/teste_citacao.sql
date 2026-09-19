-- A citação: quando resolve, quando pergunta, e quando NÃO pode chutar.
--
-- O QUE EU AFIRMEI E NÃO ERA VERDADE (01/09): escrevi que "a citação
-- resolve por igualdade de message_id". O sinal da Z-API chega mesmo, mas
-- o outro lado -- o ID guardado -- só existia para uma parte das
-- mensagens. Os dois furos, os dois medidos:
--
--   * o `postar_easy` do publicador postava e NÃO registrava. A Waldyrene
--     respondeu ao card do Smart Tower Itapuranga postado no grupo Easy e
--     a Nay teve que perguntar de qual imóvel ela falava.
--
--   * `Registrar envio` só gravava quando a resposta tinha `Código: NNNN`.
--     A Alice marcou a LISTA ("• 2943 ... • 5611 ...") e ouviu duas vezes
--     "não consigo identificar qual imóvel foi citado".
--
-- E o pior, que não era falta e sim erro: na execução 3768 o par gravado
-- foi o código do PRIMEIRO card com o message_id do QUARTO. Citar o
-- último card resolveria para o imóvel errado, com convicção.
--
--   docker cp teste_citacao.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- Um card, com rótulo: resolve direto.
INSERT INTO mensagem_saida (message_id, telefone, texto) VALUES
 ('TESTE-CARD-1', '5592900000008',
  '📍 Condomínio Acquarelle' || chr(10) || '• 2 quartos' || chr(10)
  || 'locação: 3.500' || chr(10) || 'Código: 2943');

INSERT INTO resultado
SELECT 'card citado resolve para o imóvel dele',
       coalesce(nay_imovel_da_citacao('TESTE-CARD-1'),'(nulo)'), '2943';

-- Uma LISTA, sem rótulo, com dois imóveis: PERGUNTA, e com as opções.
INSERT INTO mensagem_saida (message_id, telefone, texto) VALUES
 ('TESTE-LISTA-1', '5592900000008',
  'sim, temos no Condomínio Acquarelle:' || chr(10)
  || '• 2943 — 2 quartos — 3.500' || chr(10) || '• 5611 — 3 quartos — 4.600');

INSERT INTO resultado
SELECT 'lista com dois imóveis NÃO escolhe um',
       coalesce(nay_imovel_da_citacao('TESTE-LISTA-1'),'(nulo)'), '(nulo)';

INSERT INTO resultado
SELECT 'e devolve as opções para ela perguntar',
       CASE WHEN nay_opcoes_da_citacao('TESTE-LISTA-1') LIKE '%2943%'
             AND nay_opcoes_da_citacao('TESTE-LISTA-1') LIKE '%5611%'
            THEN 'as duas' ELSE coalesce(nay_opcoes_da_citacao('TESTE-LISTA-1'),'(nenhuma)') END,
       'as duas';

-- Valor não é código: "locação: 3.500" não pode virar o imóvel 3500.
INSERT INTO mensagem_saida (message_id, telefone, texto) VALUES
 ('TESTE-VALOR-1', '5592900000008',
  'esse aí sai por 3.500 de aluguel, com condomínio de 900');

INSERT INTO resultado
SELECT 'valor no texto não vira código',
       coalesce(nay_imovel_da_citacao('TESTE-VALOR-1'),'(nulo)'), '(nulo)';

-- ID que a gente nunca mandou: NULL, e NULL leva a perguntar.
INSERT INTO resultado
SELECT 'ID desconhecido não inventa imóvel',
       coalesce(nay_imovel_da_citacao('NUNCA-MANDEI-ISSO'),'(nulo)'), '(nulo)';

INSERT INTO resultado
SELECT 'ID vazio não quebra',
       coalesce(nay_imovel_da_citacao(''),'(nulo)'), '(nulo)';

-- `envios` continua ganhando de texto: é registro explícito, não leitura.
INSERT INTO mensagem_saida (message_id, telefone, texto) VALUES
 ('TESTE-PRIOR-1', '5592900000008', 'olha o Código: 2943 aqui');
INSERT INTO envios (codigo, telefone, destino, message_id)
VALUES ('5611', '5592900000008', 'corretor', 'TESTE-PRIOR-1');

INSERT INTO resultado
SELECT 'envios ganha do texto quando os dois existem',
       coalesce(nay_imovel_da_citacao('TESTE-PRIOR-1'),'(nulo)'), '5611';

-- Número de 3 a 5 dígitos que não é imóvel nosso: não resolve.
INSERT INTO mensagem_saida (message_id, telefone, texto) VALUES
 ('TESTE-FAKE-1', '5592900000008', 'Código: 9999');

INSERT INTO resultado
SELECT 'código que não existe no catálogo não resolve',
       coalesce(nay_imovel_da_citacao('TESTE-FAKE-1'),'(nulo)'), '(nulo)';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
