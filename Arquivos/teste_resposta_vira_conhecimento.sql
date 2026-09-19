-- O laço fecha pelo caminho que o Tel REALMENTE usa, e abre quando o
-- imóvel sai do mercado.
--
-- O CASO (auditoria de 01/09): `imovel_conhecimento` só era escrita pela
-- ferramenta do agente, e o `RESPOSTA <id>` do Tel nunca chega ao agente
-- -- o `Rotear para o agente` descarta comando. Então o laço "ele explica
-- uma vez, ela não pergunta mais" nunca fechava pelo caminho principal.
--
-- E o contrário: o VENDEU/ALUGOU limpava `imovel_conhecimento` e deixava
-- `pendencias.resposta` viva, que é onde a mesma informação estava.
--
--   docker cp teste_resposta_vira_conhecimento.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- Um imóvel de verdade do catálogo, para o reuso ter onde casar.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000002', '4946', 'valor de entrada', 'aberta');

-- O Tel responde pelo comando de sempre.
SELECT ok INTO TEMP TABLE _r
  FROM nay_responder_pendencia(
    (SELECT max(id) FROM pendencias WHERE avisar = '5592900000002'),
    'entrada de 50 mil, o resto financiado');

INSERT INTO resultado
SELECT 'RESPOSTA grava conhecimento por assunto',
       coalesce((SELECT assunto || ': ' || texto FROM imovel_conhecimento
                  WHERE codigo = '4946' AND assunto = 'entrada'), '(nada)'),
       'entrada: entrada de 50 mil, o resto financiado';

-- ... e ela passa a responder sozinha, sem escalar.
INSERT INTO resultado
SELECT 'ela já sabe, e não escala',
       coalesce((SELECT CASE WHEN sabe THEN 'sabe' ELSE 'nao sabe' END
                   FROM nay_o_que_sei_do_imovel('4946','quanto é a entrada?')), '(nulo)'),
       'sabe';

-- Resposta COM número de unidade não pode virar conhecimento: gravada,
-- seria reusada naquele imóvel para sempre. É a mesma parede do leque.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000002', '4946', 'situação do imóvel', 'aberta');
SELECT ok INTO TEMP TABLE _r2
  FROM nay_responder_pendencia(
    (SELECT max(id) FROM pendencias WHERE avisar = '5592900000002'),
    'é o apartamento 401 da torre B, está vazio');

INSERT INTO resultado
SELECT 'resposta com número de unidade NÃO vira conhecimento',
       coalesce((SELECT texto FROM imovel_conhecimento
                  WHERE codigo = '4946' AND assunto = 'situacao'), '(nada)'),
       '(nada)';

-- Pendência SEM código não vira conhecimento: sem imóvel não há reuso
-- seguro -- foi a regra de 31/08, quando código nulo virava curinga.
INSERT INTO pendencias (avisar, codigo, o_que_falta, status)
VALUES ('5592900000002', NULL, 'aceita pet', 'aberta');
SELECT ok INTO TEMP TABLE _r3
  FROM nay_responder_pendencia(
    (SELECT max(id) FROM pendencias WHERE avisar = '5592900000002'), 'aceita sim');

INSERT INTO resultado
SELECT 'pendência sem código NÃO vira conhecimento',
       (SELECT count(*)::text FROM imovel_conhecimento WHERE assunto = 'pet'
         AND texto = 'aceita sim'),
       '0';

-- O imóvel saiu do mercado: esquece nos DOIS lugares.
--
-- Em comando SEPARADO de propósito: dentro de UMA consulta, o que a
-- função escreve não é visto pelas outras partes da mesma consulta -- a
-- primeira versão deste teste falhava por isso, não por bug na função.
SELECT nay_esquecer_imovel('4946') AS apagou \gset

INSERT INTO resultado
SELECT 'VENDEU esquece conhecimento E pendência',
       (SELECT count(*)::text FROM imovel_conhecimento WHERE codigo = '4946')
       || ' / ' ||
       (SELECT count(*)::text FROM pendencias
         WHERE codigo = '4946' AND resposta IS NOT NULL),
       '0 / 0';

-- A assinatura é lida por `SELECT * INTO` dentro de `nay_comando`:
-- mudá-la quebra o RESPOSTA do Tel, e `CREATE OR REPLACE` com assinatura
-- diferente cria SOBRECARGA em vez de substituir.
INSERT INTO resultado
SELECT 'nay_responder_pendencia sem sobrecarga', count(*)::text, '1'
  FROM pg_proc WHERE proname = 'nay_responder_pendencia';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
