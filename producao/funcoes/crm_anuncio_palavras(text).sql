CREATE OR REPLACE FUNCTION public.crm_anuncio_palavras(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT string_agg(w, ' ' ORDER BY w)
    FROM (SELECT DISTINCT w FROM regexp_split_to_table(coalesce(p, ''), '[^a-z0-9]+') w WHERE w <> '') x;
$function$;
