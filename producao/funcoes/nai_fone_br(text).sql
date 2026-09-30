CREATE OR REPLACE FUNCTION public.nai_fone_br(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN d = '' THEN NULL
    WHEN length(d) IN (10, 11) AND d !~ '^55' THEN '55' || d
    WHEN length(d) IN (11, 12) AND d ~ '^0' THEN '55' || ltrim(d, '0')
    ELSE d
  END
  FROM (SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g') AS d) t;
$function$;
