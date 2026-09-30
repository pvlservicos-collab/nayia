CREATE OR REPLACE FUNCTION public.nai_lista_pt(p text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN coalesce(array_length(p, 1), 0) = 0 THEN ''
    WHEN array_length(p, 1) = 1 THEN p[1]
    ELSE array_to_string(p[1:array_length(p, 1) - 1], ', ') || ' e ' || p[array_length(p, 1)] END;
$function$;
