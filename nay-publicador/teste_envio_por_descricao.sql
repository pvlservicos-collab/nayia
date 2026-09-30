-- Prova que a Nay descobre de que imóvel o Tel fala quando ele COLA UMA
-- LISTA em vez de dar o código.
--
-- O CASO (11/09): ele pediu "Nay envia esses imóveis para o número
-- 92994717316" seguido de quatro linhas. A descoberta que define o desenho é
-- que essas linhas são saída LITERAL de `nay_linha_da_lista` -- ele está
-- colando de volta a lista que a própria Nay mandou. Então o casamento é
-- reverso e determinístico, não parecença.
--
-- As famílias de caso aqui, e por que cada uma existe:
--   1. o VALOR do jeito que ele escreve: "2.5k", "2.500", "2.6", "2.600"
--      -- quatro formas para o mesmo dinheiro, ditas por ele
--   2. as PARTES da linha, nas duas origens: a linha inteira que ela gerou
--      e a forma curta que ele digita ("Estilo Golf 2.6")
--   3. o CASAMENTO, incluindo a ambiguidade real do catálogo
--   4. o que NÃO pode virar envio: parecença, e valor que não bate
--
-- E a asserção que pega regressão sozinha: TODA linha que a Nay gera tem que
-- resolver de volta para o próprio imóvel. É o mesmo princípio do "todo
-- condomínio se identifica" -- se a formatação e o casamento andarem
-- separados, a lista que ela mandou ontem deixa de ser entendida hoje.
--
--   docker cp teste_envio_por_descricao.sql nay-postgres:/tmp/t.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/t.sql

BEGIN;

CREATE TEMP TABLE resultado(caso text, deu text, esperado text);

-- --------------------------------------------------------------------
-- 1. O VALOR, nas formas que ele escreve.
--
-- "2.500" e "2.5" dão o mesmo número de propósito: em português os dois são
-- dois mil e quinhentos, e ele usa as duas. O corte de 1.000 é o mesmo de
-- `nay_valor_curto`, que é quem produz o texto que ele cola de volta.
INSERT INTO resultado
SELECT 'valor: ' || t, coalesce(nay_valor_escrito(t)::text,'(nada)'), esperado
  FROM (VALUES
    ('2.5k',   '2500'),
    ('2.500',  '2500'),
    ('2.5',    '2500'),
    ('2.6',    '2600'),
    ('2.600',  '2600'),
    ('2.6k',   '2600'),
    ('3.500',  '3500'),
    ('5k',     '5000'),
    ('280k',   '280000'),
    ('550k',   '550000'),
    ('1.2M',   '1200000'),
    -- POR EXTENSO (15/09): "até 3 milhões" lia R$ 3.000 e devolvia aluguel.
    ('600 mil',    '600000'),
    ('250 mil',    '250000'),
    ('3 milhoes',  '3000000'),
    ('3 milhões',  '3000000'),
    ('1 milhao',   '1000000'),
    ('1.5 milhão', '1500000'),
    ('2,5 milhoes','2500000'),
    ('1.2 mi',     '1200000'),
    ('3 mil',      '3000'),
    ('650000', '650000'),
    -- o que NÃO é valor não pode virar número nenhum
    ('quartos', '(nada)'),
    ('',        '(nada)')
  ) AS v(t, esperado);

-- --------------------------------------------------------------------
-- 2. AS PARTES DA LINHA.
--
-- As seis primeiras vieram da lista dela; as seis seguintes são a forma
-- curta que ele digitou no pedido de 11/09.
INSERT INTO resultado
SELECT 'partes: ' || l.linha,
       coalesce(p.nome,'(nada)')
         || ' | q=' || coalesce(p.quartos::text,'-')
         || ' s='  || coalesce(p.suites::text,'-')
         || ' m='  || coalesce(p.area::text,'-')
         || ' R$'  || coalesce(p.valor::text,'-'),
       l.esperado
  FROM (VALUES
    ('Arezzo Residencial / 2 quartos / 2.5k',
     'Arezzo Residencial | q=2 s=- m=- R$2500'),
    ('Ariranhas / 2 quartos / 2.6k (incluso a tx)',
     'Ariranhas | q=2 s=- m=- R$2600'),
    ('Estilo Golf / 2 quartos sendo 1 suíte / 2.6k',
     'Estilo Golf | q=2 s=1 m=- R$2600'),
    -- a mobília fica no meio e não pode atrapalhar o valor
    ('Condomínio Acquarelle / 3 quartos sendo 1 suíte / mobiliado / 4.6k (incluso a tx)',
     'Condomínio Acquarelle | q=3 s=1 m=- R$4600'),
    -- sala comercial mostra m², não quartos; e a taxa POR FORA vem no fim
    ('the place / 28m2 / mobiliado / 5k / + tx de 850,00',
     'the place | q=- s=- m=28 R$5000'),
    -- "3 suítes" sem quartos: todos os quartos são suíte
    ('Morada dos pássarros / 3 suítes',
     'Morada dos pássarros | q=3 s=3 m=- R$-'),
    -- o "M" de milhão não pode ser lido como metragem
    ('Passaredo Residencial / 3 suítes / 1.2M',
     'Passaredo Residencial | q=3 s=3 m=- R$1200000'),
    -- número DENTRO do nome, antes da barra
    ('Alphaville 2 / 550k',
     'Alphaville 2 | q=- s=- m=- R$550000'),
    -- as formas curtas, ditas por ele em 11/09
    ('Arezzo 2 quartos 2.500', 'Arezzo | q=2 s=- m=- R$2500'),
    ('Ariranhas 2 quartos',    'Ariranhas | q=2 s=- m=- R$-'),
    ('Estilo Golf 2.6',        'Estilo Golf | q=- s=- m=- R$2600'),
    ('Estilo Golf 2.600',      'Estilo Golf | q=- s=- m=- R$2600'),
    ('acquarelle 2 quartos de 3.500', 'acquarelle | q=2 s=- m=- R$3500'),
    -- o "de" pendurado no fim do nome tem que sair
    ('acquarelle de 3 quartos', 'acquarelle | q=3 s=- m=- R$-'),
    -- marcador de lista colado junto
    ('- Ariranhas / 2 quartos / 2.6k', 'Ariranhas | q=2 s=- m=- R$2600'),
    -- o ✅ colado na frente de cada imóvel, formato da lista desde 15/09
    ('✅Ariranhas / 2 quartos / 2.6k (incluso a tx)', 'Ariranhas | q=2 s=- m=- R$2600')
  ) AS l(linha, esperado),
  LATERAL nay_partes_da_linha(l.linha) p;

-- --------------------------------------------------------------------
-- 3. O CASAMENTO: a linha vira código.
--
-- As quatro primeiras são o pedido literal do Tel de 11/09.
--
-- O GÊMEO DO 5719 NASCE AQUI, dentro da transação, e morre no ROLLBACK. Até
-- 14/09 este teste afirmava contra o catálogo vivo que "Estilo Golf / 2
-- quartos sendo 1 suíte / 2.6k" eram DOIS imóveis (5719 e 5728) -- e naquele
-- dia o Tel corrigiu no site: o 5728 é do Park Golf. O teste ficou vermelho
-- sem nada estar errado, o mesmo defeito do teste_lista_na_grade (bug 25):
-- asserção sobre dado de produção tem prazo de validade. O que se prova aqui é
-- a NÃO-INJETIVIDADE -- dois imóveis com a mesma linha voltam os dois --, e
-- isso o gêmeo prova para sempre.
INSERT INTO imoveis (codigo, tipo, condominio_nome, bairro, quartos, suites,
                     banheiros, valor_aluguel, disponivel, bloqueado,
                     publicado_no_site, e_parceiro, mobilia, extras,
                     taxa_condominio)
SELECT 999719, tipo, condominio_nome, bairro, quartos, suites, banheiros,
       valor_aluguel, disponivel, bloqueado, publicado_no_site, e_parceiro,
       mobilia, extras, taxa_condominio
  FROM imoveis WHERE codigo = 5719;

INSERT INTO resultado
SELECT 'casa: ' || l.linha,
       coalesce((SELECT string_agg(m.codigo, ',' ORDER BY m.codigo)
                   FROM nay_imoveis_da_linha(l.linha) m), '(nenhum)'),
       l.esperado
  FROM (VALUES
    ('Arezzo Residencial / 2 quartos / 2.5k',       '5718'),
    ('Ariranhas / 2 quartos / 2.6k (incluso a tx)', '5729'),
    -- A AMBIGUIDADE: `nay_linha_da_lista` não é injetora. Dois imóveis com
    -- os mesmos quartos, suíte e valor no mesmo condomínio rendem a MESMA
    -- string -- foi por isso que a linha veio duplicada na colagem dele em
    -- 11/09. Nenhum casamento desempata; tem que perguntar.
    ('Estilo Golf / 2 quartos sendo 1 suíte / 2.6k', '5719,999719'),
    -- as formas curtas chegam no mesmo lugar
    ('Arezzo 2 quartos 2.500',        '5718'),
    ('Ariranhas 2 quartos',           '5729'),
    ('Estilo Golf 2.6',               '5719,999719'),
    ('Estilo Golf 2.600',             '5719,999719'),
    ('acquarelle 2 quartos de 3.500', '2943'),
    -- A LINHA NO FORMATO DE 15/09, do jeito que ele copia da lista: ✅ colado.
    -- Sem tirar o marcador, o nome virava "✅Arezzo Residencial".
    ('✅Arezzo Residencial / 2 quartos / semi-mobiliado / 2.5k (incluso a tx)', '5718'),
    ('✅Estilo Golf / 2 quartos sendo 1 suíte / semi-mobiliado / 2.6k (incluso a tx)', '5719,999719'),
    -- condomínio que não existe: nenhum candidato, e isso é resposta
    ('Xanadu Imperial / 2 quartos / 3k', '(nenhum)'),
    -- valor que não bate com imóvel nenhum daquele condomínio. Dinheiro
    -- perto não é dinheiro igual: mandar o de 2.600 porque ele escreveu
    -- 2.7 seria o imóvel errado, e envio não desfaz.
    ('Estilo Golf / 2 quartos sendo 1 suíte / 2.7k', '(nenhum)')
  ) AS l(linha, esperado);

-- --------------------------------------------------------------------
-- 4. A FAIXA 5 NÃO ENVIA.
--
-- Parecença é "você quis dizer?", nunca afirmação -- a mesma parede do
-- `nay_disponibilidade_no_condominio`. Aqui seria pior que lá: afirmar manda
-- a carteira para o corretor, e isso não tem desfazer.
INSERT INTO resultado
SELECT 'faixa fraca não vira envio: ' || l.nome,
       CASE WHEN min(m.faixa) IS NULL THEN '(nenhum)'
            WHEN min(m.faixa) >= 5 THEN 'só parecença'
            ELSE 'faixa ' || min(m.faixa) END,
       l.esperado
  FROM (VALUES
    ('Liverpol', 'só parecença'),
    ('Bordeux',  'só parecença')
  ) AS l(nome, esperado)
  LEFT JOIN LATERAL nay_imoveis_da_linha(l.nome) m ON true
 GROUP BY l.nome, l.esperado;

-- --------------------------------------------------------------------
-- 5. `no_mercado` SAI JUNTO, não filtra.
--
-- Reconhecer o imóvel e poder enviá-lo são decisões diferentes -- o bug dos
-- 35 imóveis fora do site (09/09). A decisão do Tel em 11/09 foi recusar
-- DIZENDO qual; para isso o casador precisa devolver o código mesmo quando
-- o anúncio saiu do ar.
INSERT INTO resultado
SELECT 'fora do site ainda é reconhecido',
       CASE WHEN count(*) FILTER (WHERE NOT m.no_mercado) > 0
            THEN 'devolve com no_mercado=false' ELSE 'sumiu' END,
       'devolve com no_mercado=false'
  FROM nay_imoveis_da_linha('acquarelle de 3 quartos') m;

-- --------------------------------------------------------------------
-- 6. A ASSERÇÃO QUE PEGA REGRESSÃO SOZINHA.
--
-- Toda linha que a Nay GERA tem que resolver de volta para o próprio imóvel.
-- Se a formatação (`nay_linha_da_lista`) e o casamento andarem separados, a
-- lista que ela mandou ontem deixa de ser entendida hoje -- e o sintoma que
-- chega ao Tel é "não achei imóvel nenhum", sem dizer por quê.
--
-- Vale a LOCAÇÃO no mercado, que é a lista que ele cola de verdade. O
-- imóvel cuja linha é ambígua (5719/5728) conta como certo quando o próprio
-- código está entre os candidatos -- a ambiguidade é do catálogo, não do
-- casamento.
INSERT INTO resultado
SELECT 'toda linha gerada resolve de volta',
       CASE WHEN count(*) FILTER (WHERE NOT achou) = 0 THEN 'todas'
            ELSE count(*) FILTER (WHERE NOT achou) || ' não resolvem' END,
       'todas'
  FROM (
    SELECT i.codigo::text AS cod,
           EXISTS (SELECT 1
                     FROM nay_imoveis_da_linha(
                            nay_linha_da_lista(i.codigo::text,
                              nay_categoria_do_imovel(i.tipo, i.condominio_nome),
                              'locacao')) m
                    WHERE m.codigo = i.codigo::text) AS achou
      FROM imoveis i
     WHERE coalesce(i.valor_aluguel,0) > 0
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
  ) s;

-- --------------------------------------------------------------------
SELECT CASE WHEN deu = esperado THEN 'OK  ' ELSE 'ERRO' END AS r,
       caso, deu, esperado
  FROM resultado ORDER BY (deu = esperado), caso;

SELECT CASE WHEN falhas = 0
            THEN 'TODOS OS ' || total || ' CASOS PASSARAM'
            ELSE falhas || ' DE ' || total || ' FALHARAM' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE deu <> esperado) AS falhas,
               count(*) AS total FROM resultado) s;

ROLLBACK;
