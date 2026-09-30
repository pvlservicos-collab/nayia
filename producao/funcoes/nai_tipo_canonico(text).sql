CREATE OR REPLACE FUNCTION public.nai_tipo_canonico(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- Devolve o rotulo do catalogo, ou NULL quando nao da para dizer qual e.
  -- A frase tem que caber num tipo so: "apartamento ou casa" nao vale.
  SELECT CASE
    WHEN s !~ '\m(apartamento|apto|casa|cobertura|flat|sala|andar|loja|ponto|galpao|deposito|lote|terreno|chacara|sitio|predio)' THEN NULL
    WHEN (SELECT count(DISTINCT g) FROM unnest(ARRAY[
            CASE WHEN s ~ '\m(apartamento|apartamentos|apto|aptos)\M' THEN 'ap' END,
            CASE WHEN s ~ '\m(casa|casas|sobrado)\M'                  THEN 'casa' END,
            CASE WHEN s ~ '\m(cobertura|coberturas)\M'                THEN 'cob' END,
            CASE WHEN s ~ '\m(flat|flats)\M'                          THEN 'flat' END,
            CASE WHEN s ~ '\m(sala|salas|andar)\M'                    THEN 'sala' END,
            CASE WHEN s ~ '\m(loja|lojas|ponto)\M'                    THEN 'loja' END,
            CASE WHEN s ~ '\m(galpao|galpoes|deposito)\M'             THEN 'galpao' END,
            CASE WHEN s ~ '\m(lote|lotes|terreno|terrenos)\M'         THEN 'lote' END,
            CASE WHEN s ~ '\m(chacara|chacaras|sitio)\M'              THEN 'chacara' END,
            CASE WHEN s ~ '\m(predio|predios)\M'                      THEN 'predio' END
          ]) g WHERE g IS NOT NULL) <> 1 THEN NULL
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos)\M' THEN 'Apartamento'
    WHEN s ~ '\m(casa|casas|sobrado)\M'                  THEN 'Casa'
    WHEN s ~ '\m(cobertura|coberturas)\M'                THEN 'Cobertura'
    WHEN s ~ '\m(flat|flats)\M'                          THEN 'Flat'
    WHEN s ~ '\m(sala|salas|andar)\M'                    THEN 'Sala/Andar'
    WHEN s ~ '\m(loja|lojas|ponto)\M'                    THEN 'Loja/Ponto'
    WHEN s ~ '\m(galpao|galpoes|deposito)\M'             THEN 'Galpão'
    WHEN s ~ '\m(lote|lotes|terreno|terrenos)\M'         THEN 'Lote'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'              THEN 'Chácara'
    WHEN s ~ '\m(predio|predios)\M'                      THEN 'Prédio'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
