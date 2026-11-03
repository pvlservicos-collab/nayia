CREATE OR REPLACE FUNCTION public.link_organico_normal(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(lower(public.unaccent('public.unaccent'::regdictionary, coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'))
$function$;
