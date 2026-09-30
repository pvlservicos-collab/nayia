-- Ela sabe de qual imóvel a conversa está falando -- e cala quando não sabe.
--
-- O CASO (Márcio, 01 e 02/09): às 18h32 ele mandou "1327" e recebeu o card
-- da Casa em Nova Cidade. De manhã perguntou "qual o menor valor, dessa
-- casa no Nova cidade" e ouviu "me passa o código". O Tel: *"ela precisa
-- lembrar o contexto da conversa"*.
--
-- E A LINHA QUE NÃO PODE SER CRUZADA, palavra do Tel em 01/09: *"são
-- disparados mais de 3 imóveis por dia nos grupos, concluir que foi o
-- último disparado é um tiro no pé"*. Por isso este teste tem os dois
-- lados: um imóvel na conversa RESOLVE; dois ou mais PERGUNTAM; e disparo
-- de grupo não conta como conversa.
--
--   docker cp teste_imovel_em_foco.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- Conversa 1: um imóvel só, estabelecido pelo caminho do CÓDIGO PURO --
-- que é justamente o que não passa pelo agente e não entra na memória.
INSERT INTO envios (codigo, telefone, destino, message_id)
VALUES ('1327', '5592900000201', 'corretor', 'T-FOCO-1');

INSERT INTO resultado
SELECT 'um imóvel na conversa: resolve',
       coalesce(codigo,'(nulo)'), '1327' FROM nay_imovel_em_foco('5592900000201');

INSERT INTO resultado
SELECT 'e diz qual é, para ele corrigir se for outro',
       CASE WHEN descricao LIKE '%Nova Cidade%' AND descricao LIKE '%1327%'
            THEN 'diz' ELSE coalesce(descricao,'(nulo)') END, 'diz'
  FROM nay_imovel_em_foco('5592900000201');

-- Telefone com 13 dígitos (a Z-API manda ora com o 9, ora sem).
INSERT INTO resultado
SELECT 'mesmo corretor com 13 dígitos',
       coalesce(codigo,'(nulo)'), '1327' FROM nay_imovel_em_foco('55592900000201');

-- Conversa 2: dois imóveis -- PERGUNTA, com a lista, nunca escolhe.
INSERT INTO envios (codigo, telefone, destino, message_id) VALUES
 ('1327', '5592900000202', 'corretor', 'T-FOCO-2'),
 ('2943', '5592900000202', 'corretor', 'T-FOCO-3');

INSERT INTO resultado
SELECT 'dois imóveis: NÃO escolhe',
       coalesce(codigo,'(nulo)'), '(nulo)' FROM nay_imovel_em_foco('5592900000202');

INSERT INTO resultado
SELECT 'dois imóveis: devolve a lista',
       CASE WHEN opcoes LIKE '%1327%' AND opcoes LIKE '%2943%'
            THEN 'os dois' ELSE coalesce(opcoes,'(nulo)') END, 'os dois'
  FROM nay_imovel_em_foco('5592900000202');

-- Conversa 3: nunca falamos de imóvel nenhum.
INSERT INTO resultado
SELECT 'conversa sem imóvel: nada',
       coalesce(nay_aviso_do_foco('5592900000203'), '(nulo)'), '(nulo)';

-- A PAREDE DO TEL: disparo de GRUPO não é conversa. Se contasse, ela
-- concluiria pelo último imóvel postado -- o tiro no pé.
INSERT INTO envios (codigo, telefone, destino, grupo_nome, message_id)
VALUES ('5712', '120363000000000-group', 'grupo', 'Grupo de Teste', 'T-FOCO-4');

INSERT INTO resultado
SELECT 'disparo de grupo NÃO vira contexto de ninguém',
       coalesce(nay_aviso_do_foco('120363000000000-group'), '(nulo)'), '(nulo)';

-- Fora da janela: conversa de três dias atrás não é contexto de hoje.
INSERT INTO envios (codigo, telefone, destino, message_id, enviado_em)
VALUES ('4946', '5592900000204', 'corretor', 'T-FOCO-5', now() - interval '3 days');

INSERT INTO resultado
SELECT 'imóvel de 3 dias atrás não é o contexto de hoje',
       coalesce(codigo,'(nulo)'), '(nulo)' FROM nay_imovel_em_foco('5592900000204');

-- Valor que parece código não entra: a faixa deste catálogo (45 a 5712)
-- é a mesma de um valor de aluguel.
INSERT INTO mensagens (telefone, direcao, origem, texto, status)
VALUES ('5592900000205', 'recebida', 'texto', 'o cliente paga até 4000', 'Recebido');

INSERT INTO resultado
SELECT 'valor no texto não vira imóvel em foco',
       coalesce(codigo,'(nulo)'), '(nulo)' FROM nay_imovel_em_foco('5592900000205');

-- Mas o código que ELE escreveu entra.
INSERT INTO mensagens (telefone, direcao, origem, texto, status)
VALUES ('5592900000206', 'recebida', 'texto', 'me fala do 4946', 'Recebido');

INSERT INTO resultado
SELECT 'código que ele escreveu vira o contexto',
       coalesce(codigo,'(nulo)'), '4946' FROM nay_imovel_em_foco('5592900000206');

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
