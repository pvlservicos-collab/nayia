CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE COST 800
AS $function$
  -- AS RESIDENCIAIS bastam a palavra. AS COMERCIAIS exigem a marca
  -- ("sala comercial") ou o verbo do pedido ("alugar uma sala") -- medido:
  -- sem isso, 123 de 127 leituras eram falsas (120d). E "ponto de
  -- referencia/onibus/taxi" nunca e imovel (120e).
  SELECT CASE
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
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s,
               '\m(alug\w*|loc\w*|procur\w*|quer\w*|busc\w*|precis\w*|tem|teria|tenho cliente p\w*|interesse em)\s+(\w+\s+){0,2}' AS v) x;
$function$
;
