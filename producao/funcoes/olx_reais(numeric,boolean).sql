CREATE OR REPLACE FUNCTION public.olx_reais(p numeric, p_centavos boolean DEFAULT false)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p IS NULL OR p <= 0 THEN NULL
         WHEN p_centavos THEN replace(replace(replace(to_char(p, 'FM999,999,990.00'), '.', '@'), ',', '.'), '@', ',')
         ELSE replace(to_char(round(p), 'FM999,999,999'), ',', '.') END;
$function$;
