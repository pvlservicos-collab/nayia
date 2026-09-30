CREATE OR REPLACE FUNCTION public.nay_codigos_citados(p_texto text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE COST 300
AS $function$
  -- 213: o ano sai antes ("Que 2026 seja um ano..." virava o imóvel 2026)
  SELECT coalesce(array_agg(DISTINCT m[1]), ARRAY[]::text[])
    FROM regexp_matches(' ' || nay_tirar_valores(nai_tirar_anos(p_texto)) || ' ',
                        '[^0-9.,]([0-9]{3,5})[^0-9.,]', 'g') AS m;
$function$;
