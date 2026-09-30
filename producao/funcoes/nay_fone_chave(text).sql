CREATE OR REPLACE FUNCTION public.nay_fone_chave(fone text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- Brasileiro com DDI: 55 + DDD(2) + 8 ou 9 digitos.
    WHEN d ~ '^55[0-9]{10,11}$' THEN substring(d, 1, 4) || right(d, 8)
    -- Qualquer outra coisa (internacional, numero curto) fica como veio.
    ELSE d
  END
  FROM (SELECT regexp_replace(coalesce(fone, ''), '\D', '', 'g') AS d) t;
$function$;
