-- Ela não pode oferecer o outro lado da cidade.
--
-- O CASO (Waldyrene, 01/09, 22h02): a cliente queria o **Life Parque 10**,
-- no Parque 10 de Novembro. A Nay mandou quatro cards do **Acquarelle, em
-- Ponta Negra**. O Tel: "a ponta negra aonde fica o acquarelle fica
-- distante do parque dez... a ideia é enviar imóvel nos bairros ao lado
-- somente".
--
-- E o outro lado da mesma regra: quando não tem nada nem perto, ela
-- QUALIFICA (valor, quartos, bairros) em vez de empurrar o que estiver à
-- mão ou ficar repetindo que não tem.
--
--   docker cp teste_bairro_proximo.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- 1. A distância que motivou tudo.
INSERT INTO resultado VALUES
  ('Ponta Negra NÃO é perto do Parque 10',
   nay_bairro_e_perto('Parque 10 de Novembro','Ponta Negra')::text, 'false'),
  ('Aleixo É perto do Parque 10',
   nay_bairro_e_perto('Parque 10 de Novembro','Aleixo')::text, 'true'),
  ('Tarumã É perto de Ponta Negra',
   nay_bairro_e_perto('Ponta Negra','Tarumã')::text, 'true'),
  ('Cidade Nova NÃO é perto de Ponta Negra',
   nay_bairro_e_perto('Ponta Negra','Cidade Nova')::text, 'false'),
  ('bairro sem zona cadastrada não puxa ninguém',
   coalesce(array_length(nay_bairros_proximos('Bairro Que Não Existe'),1),0)::text, '0');

-- 2. A asserção que pega o caso real de ponta a ponta: em NENHUMA
--    combinação de perfil a busca no Parque 10 pode devolver um imóvel de
--    Ponta Negra.
INSERT INTO resultado
SELECT 'busca no Parque 10 nunca cita Ponta Negra',
       count(*) FILTER (WHERE d.texto_pronto ILIKE '%Ponta Negra%')::text, '0'
  FROM (VALUES ('venda'),('locacao')) n(neg),
       (VALUES (NULL),('400000'),('5000'),('1000000')) t(teto),
       (VALUES (NULL),('2'),('3'),('4')) q(qt),
       LATERAL nay_buscar_por_perfil('Parque 10 de Novembro', n.neg, t.teto, q.qt) d;

-- 3. Quando tem vizinho, ela oferece dizendo o bairro de cada um.
INSERT INTO resultado
SELECT 'oferece vizinho dizendo o bairro',
       CASE WHEN d.texto_pronto LIKE '%aqui perto eu tenho%'
             AND d.texto_pronto ~ '\(\w' THEN 'diz o bairro'
            ELSE left(replace(d.texto_pronto,chr(10),' / '),70) END,
       'diz o bairro'
  FROM nay_buscar_por_perfil('Parque 10 de Novembro','venda','400000','3') d;

INSERT INTO resultado
SELECT 'e manda NÃO oferecer outra região',
       CASE WHEN d.instrucao_para_voce LIKE '%NAO ofereca%outra regiao%'
            THEN 'manda' ELSE left(d.instrucao_para_voce,70) END,
       'manda'
  FROM nay_buscar_por_perfil('Parque 10 de Novembro','venda','400000','3') d;

-- 4. Bairro fora da área: as três perguntas, e sem escalar.
INSERT INTO resultado
SELECT 'bairro fora da área faz as três perguntas',
       CASE WHEN d.texto_pronto ILIKE '%quais outros bairros%'
             AND d.texto_pronto ILIKE '%até que valor%'
             AND d.texto_pronto ILIKE '%quantos quartos%'
            THEN 'pergunta as três' ELSE left(d.texto_pronto,80) END,
       'pergunta as três'
  FROM nay_buscar_por_perfil('Ipanema','venda',NULL,NULL) d;

-- 5. Todo bairro do catálogo tem zona: sem zona, ela não oferece nada
--    perto -- o silêncio é seguro, mas é silêncio.
INSERT INTO resultado
SELECT 'todo bairro do catálogo tem zona',
       count(*)::text, '0'
  FROM (SELECT DISTINCT bairro FROM imoveis
         WHERE coalesce(disponivel,true) AND coalesce(bairro,'') <> '') b
  LEFT JOIN bairro_zona z
    ON nay_normalizar_lugar(z.bairro,true) = nay_normalizar_lugar(b.bairro,true)
 WHERE z.bairro IS NULL;

-- 6. E os avisos de turno, contra os textos reais das duas conversas.
INSERT INTO resultado VALUES
  ('Waldyrene: pediu locação E venda',
   coalesce(nay_negocio_pedido('os dois acquareles locacao é o de 02 e 03  quartos'
            || chr(10) || 'me evia os de venda tambem'),'(nulo)'), 'ambos'),
  ('Alice: pediu visita',
   nay_pede_visita('Cliente gostaria de agendar uma visita' || chr(10)
            || 'Está disponível?')::text, 'true'),
  ('pergunta comum não vira pedido de visita',
   nay_pede_visita('esse ainda está disponível?')::text, 'false'),
  ('só locação continua sendo só locação',
   coalesce(nay_negocio_pedido('tem apartamento pra alugar no taruma?'),'(nulo)'), 'locacao');

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
