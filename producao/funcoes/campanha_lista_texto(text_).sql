CREATE OR REPLACE FUNCTION public.campanha_lista_texto(p text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN coalesce(cardinality(p), 0) = 0 THEN ''
              WHEN cardinality(p) = 1 THEN p[1]
              ELSE array_to_string(p[1:cardinality(p) - 1], ', ') || ' e ' || p[cardinality(p)] END
$function$;
