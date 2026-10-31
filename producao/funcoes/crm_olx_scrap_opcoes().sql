CREATE OR REPLACE FUNCTION public.crm_olx_scrap_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'total', (SELECT count(DISTINCT olx_id) FROM scrap_anuncio),
    'ultima_coleta', (SELECT max(coletado_em) FROM scrap_anuncio),
    'bairros', coalesce((SELECT jsonb_agg(jsonb_build_object('bairro', b, 'n', n) ORDER BY n DESC)
                           FROM (SELECT bairro AS b, count(DISTINCT olx_id) AS n FROM scrap_anuncio
                                  WHERE coalesce(bairro, '') <> '' GROUP BY 1 HAVING count(DISTINCT olx_id) >= 3) t), '[]'::jsonb));
$function$;
