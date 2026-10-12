CREATE OR REPLACE FUNCTION public.nay_fone_com_ddi(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN d ~ '^55' AND length(d) IN (12, 13) THEN d WHEN length(d) IN (10, 11) THEN '55' || d ELSE d END
    FROM (SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g') AS d) x $function$;
