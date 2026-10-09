-- A taxa de condomínio no card, e a janela de 45 dias.
--
-- O PEDIDO (Tel, 03/10/2026), com o card do 9013 por exemplo: "acrescentando
-- também a taxa de condomínio quando tem, lembrando que você coloca a taxa de
-- condomínio somente dos imóveis tem 45 dias em diante a taxa atualizada no
-- site".
--
-- O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:
--
--   * a janela CORTA. Taxa velha no card é número errado na boca do corretor,
--     e ele descobre na visita, com o cliente do lado;
--
--   * sem carimbo NÃO SAI. É o "todo portão falha FECHADO" do projeto: taxa
--     cuja data ninguém sabe é taxa cuja idade ninguém sabe;
--
--   * o CARIMBO É DO TRIGGER. Seis caminhos escrevem taxa hoje; se o carimbo
--     dependesse de cada um, o próximo esqueceria -- e esquecer não dá erro,
--     só faz a taxa parar de sair, calada;
--
--   * a taxa APAGADA perde o carimbo, senão data velha fica pendurada em campo
--     vazio e engana a próxima leitura;
--
--   * o FORMATO é o dele: "• taxa de condomínio 1092,10". Sem R$, vírgula
--     decimal, centavos sempre.
--
--   docker cp teste_taxa_do_card.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- ---------------------------------------------------------------- a regra crua
INSERT INTO resultado VALUES
 ('taxa recente sai, no formato dele',
  coalesce(nay_linha_da_taxa(1092.10, now()), '(nada)'),
  '• taxa de condomínio 1092,10'),

 ('taxa de ontem sai',
  coalesce(nay_linha_da_taxa(520, now() - interval '1 day'), '(nada)'),
  '• taxa de condomínio 520,00'),

 ('44 dias ainda sai -- a borda de dentro',
  coalesce(nay_linha_da_taxa(520, now() - interval '44 days'), '(nada)'),
  '• taxa de condomínio 520,00'),

 ('46 dias NAO sai',
  coalesce(nay_linha_da_taxa(520, now() - interval '46 days'), '(nada)'),
  '(nada)'),

 -- FALHA FECHADA: é o estado das 124 taxas do import da planilha.
 ('sem carimbo NAO sai',
  coalesce(nay_linha_da_taxa(520, NULL), '(nada)'),
  '(nada)'),

 ('taxa nula NAO sai',
  coalesce(nay_linha_da_taxa(NULL, now()), '(nada)'),
  '(nada)'),

 -- Taxa zero é "não tem taxa", não "taxa de zero reais": 616 imóveis trazem
 -- zero em lances de escada pelo mesmo motivo, e a lição já está escrita.
 ('taxa zero NAO sai',
  coalesce(nay_linha_da_taxa(0, now()), '(nada)'),
  '(nada)'),

 -- Centavos sempre, inclusive em valor redondo: "592" ao lado de "1092,10" no
 -- mesmo grupo pareceria dado de qualidade diferente.
 ('valor redondo sai com centavos',
  coalesce(nay_linha_da_taxa(592, now()), '(nada)'),
  '• taxa de condomínio 592,00'),

 -- A maior taxa do catálogo é 3.898,50. Sem ponto de milhar, como ele escreveu.
 ('taxa de quatro digitos nao leva ponto de milhar',
  coalesce(nay_linha_da_taxa(3898.50, now()), '(nada)'),
  '• taxa de condomínio 3898,50');

-- A JANELA VEM DO BANCO e muda sem deploy.
UPDATE config SET valor = '7' WHERE chave = 'card_taxa_dias';
INSERT INTO resultado VALUES
 ('a janela obedece o config: com 7 dias, 10 dias atras NAO sai',
  coalesce(nay_linha_da_taxa(520, now() - interval '10 days'), '(nada)'),
  '(nada)');
UPDATE config SET valor = '45' WHERE chave = 'card_taxa_dias';

-- ------------------------------------------------------------------- o carimbo
-- Um imóvel inventado, para não encostar em linha de verdade.
INSERT INTO imoveis (codigo, tipo, bairro, quartos, taxa_condominio,
                     disponivel, bloqueado, publicado_no_site)
VALUES (999901, 'Apartamento', 'Bairro De Teste Zzz', 2, NULL,
        true, false, true);

INSERT INTO resultado
SELECT 'nasce sem taxa: nasce sem carimbo',
       coalesce(taxa_condominio_em::text, '(nulo)'), '(nulo)'
  FROM imoveis WHERE codigo = 999901;

-- A PRIMEIRA taxa é NULL -> valor, e é o caso que um `<>` cru perderia: com
-- NULL de um lado o `<>` devolve NULL e o carimbo nunca aconteceria.
UPDATE imoveis SET taxa_condominio = 450 WHERE codigo = 999901;
INSERT INTO resultado
SELECT 'a PRIMEIRA taxa e carimbada (o IS DISTINCT FROM)',
       CASE WHEN taxa_condominio_em > now() - interval '1 minute'
            THEN 'carimbada' ELSE coalesce(taxa_condominio_em::text, '(nulo)') END,
       'carimbada'
  FROM imoveis WHERE codigo = 999901;

INSERT INTO resultado
SELECT 'e ja sai no card', coalesce(nay_linha_da_taxa(taxa_condominio, taxa_condominio_em), '(nada)'),
       '• taxa de condomínio 450,00'
  FROM imoveis WHERE codigo = 999901;

-- Envelhecer o carimbo à mão e reescrever o MESMO valor: escrever de novo o
-- mesmo número não é taxa nova, e não pode rejuvenescer o dado.
UPDATE imoveis SET taxa_condominio_em = now() - interval '200 days'
 WHERE codigo = 999901;
UPDATE imoveis SET taxa_condominio = 450 WHERE codigo = 999901;
INSERT INTO resultado
SELECT 'reescrever o MESMO valor nao rejuvenesce o carimbo',
       CASE WHEN taxa_condominio_em < now() - interval '100 days'
            THEN 'continua velho' ELSE 'rejuvenesceu' END, 'continua velho'
  FROM imoveis WHERE codigo = 999901;

INSERT INTO resultado
SELECT 'e por isso NAO sai no card',
       coalesce(nay_linha_da_taxa(taxa_condominio, taxa_condominio_em), '(nada)'),
       '(nada)'
  FROM imoveis WHERE codigo = 999901;

-- Valor DIFERENTE é taxa nova: carimba e volta a sair.
UPDATE imoveis SET taxa_condominio = 480 WHERE codigo = 999901;
INSERT INTO resultado
SELECT 'valor diferente carimba de novo',
       coalesce(nay_linha_da_taxa(taxa_condominio, taxa_condominio_em), '(nada)'),
       '• taxa de condomínio 480,00'
  FROM imoveis WHERE codigo = 999901;

-- Apagar a taxa apaga o carimbo.
UPDATE imoveis SET taxa_condominio = NULL WHERE codigo = 999901;
INSERT INTO resultado
SELECT 'taxa apagada perde o carimbo',
       coalesce(taxa_condominio_em::text, '(nulo)'), '(nulo)'
  FROM imoveis WHERE codigo = 999901;

-- UPDATE que NAO menciona a taxa nao mexe no carimbo -- a varredura escreve
-- dez colunas por linha e não pode carimbar taxa de tabela.
UPDATE imoveis SET taxa_condominio = 300 WHERE codigo = 999901;
UPDATE imoveis SET taxa_condominio_em = now() - interval '10 days'
 WHERE codigo = 999901;
UPDATE imoveis SET bairro = 'Outro Bairro Zzz' WHERE codigo = 999901;
INSERT INTO resultado
SELECT 'UPDATE em outra coluna nao mexe no carimbo',
       CASE WHEN taxa_condominio_em < now() - interval '9 days'
            THEN 'intacto' ELSE 'mexeu' END, 'intacto'
  FROM imoveis WHERE codigo = 999901;

-- --------------------------------------------------------- o catálogo de hoje
-- O 9013 é o imóvel do exemplo dele, e o card dele TEM que trazer a linha --
-- senão o pedido não foi atendido no caso que ele mostrou.
INSERT INTO resultado
SELECT 'o 9013 do exemplo dele mostra a taxa',
       coalesce(nay_linha_da_taxa(taxa_condominio, taxa_condominio_em), '(nada)'),
       '• taxa de condomínio 1092,10'
  FROM imoveis WHERE codigo = 9013;

-- E o card montado pelo banco tem que trazer a linha de verdade, não só a
-- função solta: é o card que a Nay serve quando não há ficha do anúncio.
INSERT INTO resultado
SELECT 'o card do banco do 9013 traz a linha',
       CASE WHEN texto_pronto LIKE '%• taxa de condomínio 1092,10%'
            THEN 'traz' ELSE texto_pronto END, 'traz'
  FROM nai_card_do_imovel(9013);

-- Nenhum card pode mostrar taxa sem carimbo, no catálogo inteiro.
INSERT INTO resultado
SELECT 'nenhuma taxa sem carimbo vira linha (catalogo inteiro)',
       (SELECT count(*) FROM imoveis
         WHERE coalesce(taxa_condominio, 0) > 0
           AND taxa_condominio_em IS NULL
           AND nay_linha_da_taxa(taxa_condominio, taxa_condominio_em) IS NOT NULL
       )::text, '0';

SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
