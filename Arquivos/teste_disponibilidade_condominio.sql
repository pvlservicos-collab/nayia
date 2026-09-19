-- Prova que a Nay reconhece o condomínio pelo NOME -- e que ela cala a
-- boca quando não reconhece.
--
-- O CASO (01/09): o Erick colou o anúncio do Liverpool. A primeira versão
-- desta função acertava a palavra solta "Liverpool" e ERRAVA o nome
-- completo "Liverpool Reserva Inglesa" -- ou seja, quanto mais preciso o
-- corretor, pior a resposta. E o que vem colado num anúncio é sempre o
-- nome completo.
--
-- As três famílias de caso aqui, e por que cada uma existe:
--   1. as 7 formas reais de repassar o anúncio do Erick -> todas resolvem
--   2. a ambiguidade DELIBERADA ("Reserva Inglesa" é o Liverpool E o
--      London) -> continua perguntando
--   3. o que ela NÃO pode afirmar: nome parecido, condomínio só de
--      parceiro, condomínio inteiro bloqueado
--
-- E a asserção que pega regressão sozinha: TODO nome do catálogo tem que
-- se resolver a si mesmo. Na primeira versão, 47 de 159 não se resolviam
-- -- e como a lista de desambiguação oferece o nome exato, escolher a
-- opção oferecida devolvia a mesma pergunta. Laço fechado.
--
--   docker cp teste_disponibilidade_condominio.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- 1. As sete formas do Erick. Ele perguntou LOCAÇÃO, e o Liverpool só tem
--    venda -- a resposta certa é a mesma que o Tel deu à mão
--    ("o Liverpool alugou, não está mais disponível").
INSERT INTO resultado
SELECT 'Erick: ' || f.forma,
       CASE WHEN d.texto_pronto LIKE 'no Liverpool Reserva Inglesa não tenho nada para locação%'
            THEN 'resolve' ELSE d.texto_pronto END,
       'resolve'
  FROM (VALUES
   ('Liverpool'),
   ('Liverpool Reserva Inglesa'),
   ('Condominio Liverpool Reserva Inglesa'),
   ('Condomínio Liverpool (Reserva Inglesa)'),
   ('Liverpool (Reserva Inglesa)'),
   ('Condomínio Parque Reserva Inglesa - Liverpool'),
   ('Reserva Inglesa - Liverpool')) f(forma),
   LATERAL nay_disponibilidade_no_condominio(f.forma,'locacao') d;

-- 2. Ambiguidade que TEM que continuar existindo. Responder por um só
--    seria informação do imóvel errado.
INSERT INTO resultado
SELECT 'ambíguo de propósito: ' || f.forma,
       CASE WHEN d.texto_pronto LIKE 'temos mais de um%' THEN 'pergunta'
            ELSE left(replace(d.texto_pronto, chr(10),' / '),60) END,
       'pergunta'
  FROM (VALUES ('Reserva Inglesa'),('Alphaville')) f(forma),
   LATERAL nay_disponibilidade_no_condominio(f.forma,NULL) d;

-- 3. Nome parecido NÃO afirma nada. Antes, "Vila Verde 1" (um L a menos)
--    respondia com firmeza sobre o Parque Verde, que é outro condomínio.
INSERT INTO resultado
SELECT 'parecido não afirma: ' || f.forma,
       CASE WHEN d.texto_pronto LIKE 'você quis dizer%' THEN 'pergunta'
            ELSE left(replace(d.texto_pronto, chr(10),' / '),60) END,
       'pergunta'
  FROM (VALUES ('Liverpol'),('Bordeux'),('Vila Verde 1'),('Ajuricab')) f(forma),
   LATERAL nay_disponibilidade_no_condominio(f.forma,NULL) d;

-- 4. Condomínio que existe mas é só de parceiro NÃO pode ser declarado
--    inexistente. Era o buraco maior: 177 de 387 nomes.
INSERT INTO resultado
SELECT 'só parceria: ' || f.forma,
       CASE WHEN d.texto_pronto LIKE '%imóvel de parceria%' THEN 'parceria'
            ELSE left(replace(d.texto_pronto, chr(10),' / '),60) END,
       'parceria'
  FROM (VALUES ('Villa Verde 1'),('Lê Boulevard'),('Smart Vista do Sol 2')) f(forma),
   LATERAL nay_disponibilidade_no_condominio(f.forma,'venda') d;

-- 5. Condomínio que não existe em lugar nenhum: aí sim é "não temos".
--    Decisão do Tel: isso é resposta, não motivo de escalar.
INSERT INTO resultado
SELECT 'não existe mesmo',
       CASE WHEN d.texto_pronto LIKE 'não temos imóvel%'
             AND d.instrucao_para_voce LIKE '%NAO chame escalar_ao_tel%'
            THEN 'nao temos' ELSE left(d.texto_pronto,60) END,
       'nao temos'
  FROM nay_disponibilidade_no_condominio('Condomínio Fantasma','venda') d;

-- 6. Nome vazio, e nome que só tem palavra genérica ("Apartamento" e
--    "Casa" são condominio_nome de verdade no cadastro, e a chave deles
--    fica vazia -- chave vazia casava com tudo).
INSERT INTO resultado
SELECT 'sem nome: ' || coalesce(f.forma,'(null)'),
       CASE WHEN d.texto_pronto LIKE 'de qual condomínio%' THEN 'pergunta'
            ELSE left(d.texto_pronto,60) END,
       'pergunta'
  FROM (VALUES (''),('Apartamento'),('condomínio')) f(forma),
   LATERAL nay_disponibilidade_no_condominio(f.forma,NULL) d;

-- 7. Nenhum caminho pode dizer "sim, temos" com lista vazia. Hoje nenhum
--    condomínio está inteiro bloqueado -- é um UPDATE de distância.
UPDATE imoveis SET bloqueado = true WHERE condominio_nome = 'Bordeaux';
INSERT INTO resultado
SELECT 'condomínio inteiro bloqueado',
       CASE WHEN d.texto_pronto LIKE '%não tenho nada disponível%' THEN 'nao temos'
            ELSE left(replace(d.texto_pronto, chr(10),' / '),60) END,
       'nao temos'
  FROM nay_disponibilidade_no_condominio('Bordeaux',NULL) d;

-- A asserção que pega regressão sozinha, contra o catálogo INTEIRO: todo
-- condomínio tem que se resolver a si mesmo. Ela entra no mesmo balde dos
-- outros casos de propósito -- asserção que não conta no resumo é
-- decoração, e este arquivo existe justamente porque uma suite verde
-- deixou de provar o que dizia provar.
INSERT INTO resultado
SELECT 'todo condomínio do catálogo se identifica',
       CASE WHEN n = 0 THEN 'todos'
            ELSE n || ' não conseguem' END, 'todos'
  FROM (SELECT count(*) AS n
          FROM (SELECT DISTINCT condominio_nome AS nome FROM imoveis
                 WHERE coalesce(condominio_nome,'') <> '') c,
               LATERAL nay_disponibilidade_no_condominio(c.nome, NULL) d
         WHERE d.texto_pronto LIKE 'temos mais de um%'
            OR d.texto_pronto LIKE 'você quis dizer%'
            OR d.texto_pronto LIKE 'não temos imóvel no %') s;

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
