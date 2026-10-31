CREATE OR REPLACE FUNCTION public.geo_imovel_perto_refazer(p_codigo integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n integer;
BEGIN
  DELETE FROM geo_imovel_perto WHERE p_codigo IS NULL OR codigo = p_codigo;
  INSERT INTO geo_imovel_perto (codigo, bairro, km)
  SELECT g.codigo, b.bairro,
         CASE WHEN nay_normalizar_lugar(coalesce(i.bairro, g.bairro, ''), true) = nay_normalizar_lugar(b.bairro, true) THEN 0
              ELSE round(min(111.2 * sqrt(power((v.pt->>1)::float8 - g.lat, 2)
                                          + power(((v.pt->>0)::float8 - g.lon) * cos(radians(g.lat)), 2)))::numeric, 2) END
    FROM imovel_geo g
    LEFT JOIN imoveis i ON i.codigo = g.codigo
    JOIN geo_bairro b ON b.poligono IS NOT NULL AND abs(b.lat - g.lat) < 0.2 AND abs(b.lon - g.lon) < 0.2
    CROSS JOIN LATERAL jsonb_array_elements(b.poligono->'coordinates'->0) v(pt)
   WHERE (p_codigo IS NULL OR g.codigo = p_codigo) AND b.poligono->>'type' = 'Polygon'
   GROUP BY g.codigo, b.bairro, i.bairro, g.bairro
  HAVING nay_normalizar_lugar(coalesce(i.bairro, g.bairro, ''), true) = nay_normalizar_lugar(b.bairro, true)
      OR min(111.2 * sqrt(power((v.pt->>1)::float8 - g.lat, 2)
                          + power(((v.pt->>0)::float8 - g.lon) * cos(radians(g.lat)), 2))) <= 8;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$function$;
