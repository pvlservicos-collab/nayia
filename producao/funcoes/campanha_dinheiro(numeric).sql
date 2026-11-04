CREATE OR REPLACE FUNCTION public.campanha_dinheiro(p numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p IS NULL OR p <= 0 THEN NULL ELSE 'R$ ' || replace(to_char(round(p), 'FM999,999,999,990'), ',', '.') END
$function$;
