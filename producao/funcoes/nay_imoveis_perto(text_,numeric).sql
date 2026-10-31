CREATE OR REPLACE FUNCTION public.nay_imoveis_perto(p_bairros text[], p_km numeric DEFAULT 2.0)
 RETURNS TABLE(codigo integer, km numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- os imóveis a até p_km da borda de algum dos bairros pedidos; os que ficam DENTRO de um deles não entram (são
  -- "no bairro", não "ao redor")
  WITH ped AS (SELECT DISTINCT nay_normalizar_lugar(b, true) AS n FROM unnest(p_bairros) b WHERE coalesce(btrim(b), '') <> '')
  SELECT p.codigo, min(p.km)
    FROM geo_imovel_perto p
   WHERE nay_normalizar_lugar(p.bairro, true) IN (SELECT n FROM ped) AND p.km <= p_km
     AND NOT EXISTS (SELECT 1 FROM geo_imovel_perto d WHERE d.codigo = p.codigo AND d.km = 0
                       AND nay_normalizar_lugar(d.bairro, true) IN (SELECT n FROM ped))
   GROUP BY p.codigo;
$function$;
