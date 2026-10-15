CREATE OR REPLACE FUNCTION public.olx_fone_bonito(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
           WHEN length(d) = 11 THEN left(d,2) || ' ' || substr(d,3,5) || '-' || right(d,4)
           WHEN length(d) = 10 THEN left(d,2) || ' ' || substr(d,3,4) || '-' || right(d,4)
           ELSE nullif(d, '')
         END
    FROM (SELECT regexp_replace(coalesce(p,''), '\D', '', 'g')) AS x(d);
$function$;
