CREATE OR REPLACE FUNCTION public.scrap_telefone_formatar(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p IS NULL THEN NULL
              WHEN length(p) = 11 THEN '(' || left(p, 2) || ') ' || substr(p, 3, 5) || '-' || substr(p, 8)
              WHEN length(p) = 10 THEN '(' || left(p, 2) || ') ' || substr(p, 3, 4) || '-' || substr(p, 7)
              ELSE p END
$function$;
