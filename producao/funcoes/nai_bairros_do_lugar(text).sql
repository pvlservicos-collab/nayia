CREATE OR REPLACE FUNCTION public.nai_bairros_do_lugar(p_texto text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT array_agg(DISTINCT b ORDER BY b) FROM nai_lugar_citado(p_texto) l, unnest(l.bairros) b;
$function$;
