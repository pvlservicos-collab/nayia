CREATE OR REPLACE FUNCTION public.nay_codigos_citados(p_texto text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE COST 300
AS $function$
  SELECT coalesce(array_agg(DISTINCT m[1]), ARRAY[]::text[])
    FROM regexp_matches(' ' || nay_tirar_valores(p_texto) || ' ',
                        '[^0-9.,]([0-9]{3,5})[^0-9.,]', 'g') AS m;
$function$;
