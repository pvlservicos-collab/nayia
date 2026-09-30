CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE COST 800
AS $function$
  -- AS RESIDENCIAIS bastam a palavra. AS COMERCIAIS exigem a marca
  -- ("sala comercial") ou o verbo do pedido ("alugar uma sala") -- medido:
  -- sem isso, 123 de 127 leituras eram falsas (120d). E "ponto de
  -- referencia/onibus/taxi" nunca e imovel (120e).
  -- 224: a palavra so conta quando e o pedido. Fora: a negacao ("nao e a casa
  -- nao, e o Smart Tower" era lido como casa -- Marcio, 30/09), a casa de quem
  -- escreve ("cheguei em casa", "saindo de casa"), nome de condominio
  -- ("Amazonas Flat" tem 22 apartamentos), link, e a descricao de foto que o
  -- sistema escreve ("a imagem mostra ... muitas casas").
  SELECT CASE
    WHEN s0 ~ '^\s*(o|a|os|as|este|esse|esta|essa)\s+(arquivo|imagem|documento|print|foto|video|audio|pdf)s?\s+(mostra|apresenta|e|eh|contem|traz|exibe|parece|tem|possui)\M'
                                                            THEN NULL
    WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
    WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
    WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
    WHEN s ~ '\m(salas?|conjuntos?)\s+(comercial|comerciais)\M'
      OR   s ~ (v || 'salas?\M')                            THEN 'Sala%'
    WHEN s ~ '\m(lojas?|pontos?)\s+(comercial|comerciais)\M'
      OR   (s ~ (v || '(lojas?|pontos?)\M')
            AND NOT s ~ '\mpontos?\s+de\s+(referencia|onibus|taxi|encontro)\M')
                                                            THEN 'Loja%'
    WHEN s ~ '\m(galpao|galpoes)\M'
      OR   s ~ (v || 'depositos?\M')                        THEN 'Galp%'
    WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
    WHEN s ~ (v || 'predios?\M')                            THEN 'Pr%dio%'
  END
  FROM (SELECT s0,
               regexp_replace(regexp_replace(regexp_replace(regexp_replace(s0,
                 '(https?://|www\.)\S+', ' ', 'g'),
                 '\mnao\s+(e|eh|era|seria|quero|queria|precisa ser|pode ser|serve|busco|procuro|preciso de)\s+(uma?\s+|a\s+|o\s+|de\s+)?(casas?|sobrados?|apartamentos?|aptos?|ap|flats?|coberturas?)\M', ' ', 'g'),
                 '\m(cheguei|chegar|chego|chegando|chegou|sai|sair|saindo|saio|saiu|voltei|voltar|voltando|volto|indo|vou|to|estou|esta|estava|estarei|fico|fiquei|ficar|ficando|trabalho|trabalhando|trabalhar|la)\s+(de|em|na|pra|para)\s+(a\s+)?casa\M', ' ', 'g'),
                 '\m(amazonas?\s+flat|flat\s+edificio|condominio\s+flat|casa\s+center)\M', ' ', 'g') AS s,
               '\m(alug\w*|loc\w*|procur\w*|quer\w*|busc\w*|precis\w*|tem|teria|tenho cliente p\w*|interesse em)\s+(\w+\s+){0,2}' AS v
          FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s0) a) x;
$function$;
