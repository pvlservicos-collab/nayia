CREATE OR REPLACE FUNCTION public.site_captacao_chave(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT btrim(regexp_replace(lower(unaccent(coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'));
$function$;
