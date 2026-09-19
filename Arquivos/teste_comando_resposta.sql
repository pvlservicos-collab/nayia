-- O comando `RESPOSTA <id>` -- o caminho que o Tel mais usa, e o único
-- que fala com o corretor sem ninguém revisar no meio.
--
-- O CASO (01/09, 19h16): o Tel escreveu **"resposta 81 descartar"**
-- querendo jogar fora a pendência. A gramática leu isso como RESPOSTA com
-- o texto "descartar", e o Valois -- que tinha perguntado "somente 2 vagas
-- de garagem?" -- recebeu "o Condomínio Itapuranga III, descartar".
-- Quarenta e cinco segundos depois ele respondeu "Não anunciar?".
--
-- Nenhuma resposta de verdade é SÓ um verbo de descarte, então tratar
-- isso como DESCARTAR não perde ambiguidade nenhuma.
--
-- E o outro caso, de 13h17 do mesmo dia: "resposta 49 já foi negociado
-- Erick" quando ele queria a 48. Um dígito. A confirmação passou a dizer
-- para QUEM foi e sobre O QUÊ, para o erro aparecer no segundo seguinte.
--
--   docker cp teste_comando_resposta.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

INSERT INTO corretores (telefone, nome, aprovado, ativo)
VALUES ('5592900000006', 'Valois de Teste', true, true)
ON CONFLICT DO NOTHING;

INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000006', '5035', 'vagas de garagem', 'aberta');

-- 1. CASO REAL: "resposta <id> descartar" não pode virar mensagem.
SELECT c.msg_corretor AS mc, c.msg_tel AS mt
  INTO TEMP TABLE _d
  FROM nay_comando('RESPOSTA',
        (SELECT max(id)::text FROM pendencias WHERE avisar='5592900000006'),
        'descartar') c;

INSERT INTO resultado
SELECT 'CASO REAL: "resposta 81 descartar" não manda nada ao corretor',
       coalesce(mc, '(nada)'), '(nada)' FROM _d;

INSERT INTO resultado
SELECT 'e a pendência fica descartada, sem resposta',
       status || '/' || coalesce(resposta,'(vazia)'), 'descartada/(vazia)'
  FROM pendencias WHERE avisar = '5592900000006';

-- 2. A resposta de verdade continua funcionando, e a confirmação diz
--    para quem e sobre o quê -- é ela que faz um dígito errado aparecer.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000006', '5035', 'aceita pet', 'aberta');

SELECT c.msg_corretor AS mc, c.msg_tel AS mt
  INTO TEMP TABLE _r
  FROM nay_comando('RESPOSTA',
        (SELECT max(id)::text FROM pendencias WHERE avisar='5592900000006'),
        'aceita sim, até dois') c;

INSERT INTO resultado
SELECT 'resposta de verdade chega ao corretor',
       CASE WHEN mc LIKE '%aceita sim, até dois' THEN 'chegou' ELSE coalesce(mc,'(nada)') END,
       'chegou' FROM _r;

INSERT INTO resultado
SELECT 'a confirmação diz para QUEM e sobre O QUÊ',
       CASE WHEN mt LIKE '%Mandei para Valois%aceita pet%(imovel 5035)%'
            THEN 'diz' ELSE coalesce(mt,'(nada)') END,
       'diz' FROM _r;

-- 3. E os outros verbos de descarte, que o Tel escreve de todo jeito.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000006', '5035', 'terceira', 'aberta');

INSERT INTO resultado
SELECT 'variação "esquece" também não vira mensagem',
       coalesce(c.msg_corretor, '(nada)'), '(nada)'
  FROM nay_comando('RESPOSTA',
        (SELECT max(id)::text FROM pendencias WHERE avisar='5592900000006'),
        'esquece') c;

-- 4. O que NÃO pode virar descarte: uma resposta que só CONTÉM a palavra.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000006', '5035', 'quarta', 'aberta');

INSERT INTO resultado
SELECT 'resposta que só contém a palavra continua sendo resposta',
       CASE WHEN c.msg_corretor LIKE '%pode descartar aquela proposta%'
            THEN 'chegou' ELSE coalesce(c.msg_corretor,'(nada)') END,
       'chegou'
  FROM nay_comando('RESPOSTA',
        (SELECT max(id)::text FROM pendencias WHERE avisar='5592900000006'),
        'pode descartar aquela proposta, o valor é outro') c;

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
