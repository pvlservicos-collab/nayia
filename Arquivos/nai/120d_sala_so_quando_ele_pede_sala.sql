-- =====================================================================
-- NAI -- 120d: sala so quando ele pede sala (24/09/2026)
--
-- MEDIDO nas mensagens de verdade dos ultimos 90 dias: 127 mensagens foram
-- lidas como "ele procura sala ou loja comercial". QUATRO eram. As outras
-- 123 sao estas:
--
--     "10 andar"                        94 vezes  -> 'andar' casava com Sala
--     "03 suites, sala ampla, cozinha"  25 vezes  -> 'sala' dentro de anuncio
--     "qual e o ponto de referencia?"    7 vezes  -> 'ponto' casava com Loja
--     "estou orcando com algumas lojas"  1 vez
--
-- Foi um desses 94 que apagou o Park Golf: o corretor disse "acho que e
-- decimo andar, se nao me falha a memoria" e a Nay guardou "ele procura
-- sala". Dois dias depois ela engoliu a resposta inteira sobre o imovel que
-- ele tinha perguntado pelo nome.
--
-- A REGRA NOVA. Casa, apartamento, cobertura, flat, terreno e chacara
-- continuam como estavam: a palavra basta, porque ela so aparece quando o
-- assunto e essa. As COMERCIAIS -- sala, loja, ponto, galpao, deposito,
-- predio -- passam a exigir uma das duas coisas:
--
--     a marca comercial     "sala comercial", "ponto comercial"
--     ou o verbo do pedido  "alugar uma sala", "tem sala pra alugar"
--
-- 'andar' sai inteiro: andar e onde o apartamento fica, nunca o que ele
-- procura.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---- primeiro os casos, ainda vermelhos --------------------------------
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Park Golf 22/09', 'Acho que é décimo andar, se não me falha a memória', 'tipo', '-',
  'andar é onde o apartamento fica, não um tipo de imóvel'),
 ('Aleixo 90d',      'E qual é o ponto de referência no Aleixo?', 'tipo', '-',
  'ponto de referência não é ponto comercial'),
 ('anúncio 90d',     '450m², 03 suítes, sala ampla, cozinha americana', 'tipo', '-',
  'sala dentro da descrição não é pedido de sala comercial'),
 ('orçamento 90d',   'Estou orçando com algumas lojas e o valor muda', 'tipo', '-',
  'loja de material não é imóvel'),
 ('comercial',       'preciso alugar uma sala comercial no centro', 'tipo', 'Sala%',
  'quem pede sala comercial recebe sala'),
 ('comercial',       'tem sala pra alugar no Vieiralves?', 'tipo', 'Sala%',
  'o verbo do pedido também vale'),
 ('comercial',       'procuro um ponto comercial na Djalma', 'tipo', 'Loja%',
  'ponto comercial é loja');

\echo '=== ANTES do conserto (tem que ter vermelho) ==='
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

-- ---- agora o conserto ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Devolve o padrao que casa com `imoveis.tipo`. A ordem e a mesma de
  -- `nai_imovel_pela_descricao`: "casa" antes de "condominio", senao "casa de
  -- condominio" cai no lugar errado. 'Casa%' pega as 25 casas e as 83 casas de
  -- condominio; 'Apartamento%' pega os 134 e o "em Via Publica".
  --
  -- AS RESIDENCIAIS bastam a palavra. AS COMERCIAIS exigem a marca
  -- ("sala comercial") ou o verbo do pedido ("alugar uma sala") -- medido:
  -- sem isso, 123 de 127 leituras eram falsas (120d).
  SELECT CASE
    WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
    WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
    WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
    WHEN s ~ '\m(salas?|conjuntos?)\s+(comercial|comerciais)\M'
      OR   s ~ (v || 'salas?\M')                            THEN 'Sala%'
    WHEN s ~ '\m(lojas?|pontos?)\s+(comercial|comerciais)\M'
      OR   s ~ (v || '(lojas?|pontos?)\M')                  THEN 'Loja%'
    WHEN s ~ '\m(galpao|galpoes)\M'
      OR   s ~ (v || 'depositos?\M')                        THEN 'Galp%'
    WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
    WHEN s ~ (v || 'predios?\M')                            THEN 'Pr%dio%'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s,
               -- o verbo do pedido, ate duas palavras antes do tipo
               '\m(alug\w*|loc\w*|procur\w*|quer\w*|busc\w*|precis\w*|tem|teria|tenho cliente p\w*|interesse em)\s+(\w+\s+){0,2}' AS v) x;
$function$;

\echo '=== DEPOIS do conserto ==='
SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

COMMIT;

-- =====================================================================
-- COMO DESFAZER -- a definicao de antes, inteira:
--
-- CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
--  RETURNS text LANGUAGE sql IMMUTABLE AS $f$
--   SELECT CASE
--     WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
--     WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
--     WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
--     WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
--     WHEN s ~ '\m(sala|salas|andar)\M'                       THEN 'Sala%'
--     WHEN s ~ '\m(loja|lojas|ponto)\M'                       THEN 'Loja%'
--     WHEN s ~ '\m(galpao|galpoes|deposito)\M'                THEN 'Galp%'
--     WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
--     WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
--     WHEN s ~ '\m(predio|predios)\M'                         THEN 'Pr%dio%'
--   END
--   FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
-- $f$;
-- =====================================================================
