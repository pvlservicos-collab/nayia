CREATE OR REPLACE FUNCTION public.nai_lugar_normal(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z0-9]+', ' ', 'g'));
$function$;
