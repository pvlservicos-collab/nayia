CREATE OR REPLACE FUNCTION public.nai_bairros_ao_redor(p_bairros text[])
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  WITH ped AS (SELECT DISTINCT nay_normalizar_lugar(b, true) AS n FROM unnest(p_bairros) b WHERE coalesce(btrim(b), '') <> ''),
  viz AS (SELECT nay_normalizar_lugar(v.vizinho, true) AS n, min(v.km) AS km
            FROM geo_bairro_vizinho v JOIN ped ON nay_normalizar_lugar(v.bairro, true) = ped.n
           WHERE v.divisa OR v.km <= 3
           GROUP BY 1),
  cat AS (SELECT DISTINCT i.bairro, nay_normalizar_lugar(i.bairro, true) AS n
            FROM imoveis i WHERE coalesce(btrim(i.bairro), '') <> ''),
  junto AS (SELECT c.bairro, min(viz.km) AS km
              FROM viz JOIN cat c ON c.n = viz.n OR viz.n LIKE c.n || ' %'   -- "dom pedro i" x "Dom Pedro"
             WHERE c.n NOT IN (SELECT n FROM ped)
             GROUP BY c.bairro)
  SELECT coalesce(
    (SELECT array_agg(bairro ORDER BY km) FROM junto),
    -- o mapa não conhece o bairro: a regra antiga (a zona), sem o próprio pedido
    (SELECT array_agg(b) FROM unnest(nay_bairros_proximos(p_bairros[1])) b WHERE b <> ALL (p_bairros)));
$function$;
