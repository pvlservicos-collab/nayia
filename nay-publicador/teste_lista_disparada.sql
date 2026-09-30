-- A trava de repetição do `Nay dispara lista ...` (09/09).
--
-- POR QUE ESTE TESTE: o CLAUDE.md registra que `postar_agora` **não tem
-- proteção contra repetição**, e que reenviar posta duas vezes em 14 grupos,
-- sem desfazer. O disparo de lista é o mesmo risco com um comando mais curto
-- de digitar -- e o Tel escreve olhando o WhatsApp, onde uma mensagem que
-- "não saiu" convida a mandar de novo.
--
-- Os dois lados têm que valer: a trava segura a repetição E o escape ("de
-- novo") passa por cima dela. Trava sem escape vira parede, e parede que o
-- dono não abre acaba desligada.
--
--   docker cp teste_lista_disparada.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- 1. O primeiro disparo reserva.
INSERT INTO resultado
SELECT 'primeiro disparo: reserva',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'parceiros');

-- 2. O mesmo comando, de novo, dentro da janela: NÃO reserva, e diz quando
--    saiu -- é o que o publicador devolve ao Tel.
INSERT INTO resultado
SELECT 'repetido na janela: recusa',
       CASE WHEN id IS NULL AND ja_foi_em IS NOT NULL
            THEN 'recusou e diz quando' ELSE 'reservou' END,
       'recusou e diz quando'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'parceiros');

-- 3. OUTRA categoria não é a mesma lista -- a trava é por comando, não geral.
INSERT INTO resultado
SELECT 'outra categoria passa',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('sala', 'locacao', 'parceiros');

-- 4. O MESMO comando para OUTRO destino também passa: mandar a lista nos
--    grupos de parceiro e no grupo do Easy são duas coisas, e o Tel faz as
--    duas no mesmo dia.
INSERT INTO resultado
SELECT 'mesmo comando, destino Easy, passa',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'easy');

-- 5. Venda e locação não se confundem.
INSERT INTO resultado
SELECT 'mesma categoria, venda, passa',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'venda', 'parceiros');

-- 6. O ESCAPE: "de novo" força, mesmo dentro da janela.
INSERT INTO resultado
SELECT 'forçado passa por cima da trava',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'parceiros', true);

-- 7. A janela mora em `config` e muda com um UPDATE, sem deploy. Com zero
--    minuto, o mesmo comando volta a valer na hora.
UPDATE config SET valor = '0' WHERE chave = 'lista_repete_minutos';
INSERT INTO resultado
SELECT 'janela zerada libera na hora',
       CASE WHEN id IS NOT NULL THEN 'reservou' ELSE 'recusou' END, 'reservou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'parceiros');

-- 8. E a janela grande segura de novo -- provando que é ela que decide, e
--    não a ordem das chamadas.
UPDATE config SET valor = '600' WHERE chave = 'lista_repete_minutos';
INSERT INTO resultado
SELECT 'janela grande segura de novo',
       CASE WHEN id IS NULL THEN 'recusou' ELSE 'reservou' END, 'recusou'
  FROM nay_reservar_disparo_de_lista('apartamento', 'locacao', 'parceiros');

-- 9. A linha guarda o que saiu, para dar para responder "essa lista já foi?"
--    sem depender da memória de ninguém.
UPDATE lista_disparada SET quantos = 18, grupos = ARRAY['Grupo A', 'Grupo B']
 WHERE categoria = 'sala';
INSERT INTO resultado
SELECT 'registra quantos imóveis e quais grupos',
       coalesce(quantos::text, '(nulo)') || ' em ' ||
       coalesce(array_length(grupos, 1)::text, '(nulo)'), '18 em 2'
  FROM lista_disparada WHERE categoria = 'sala';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
