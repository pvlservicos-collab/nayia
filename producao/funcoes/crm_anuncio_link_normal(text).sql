CREATE OR REPLACE FUNCTION public.crm_anuncio_link_normal(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT nullif(regexp_replace(regexp_replace(regexp_replace(
           lower(btrim(coalesce(p, ''))), '^https?://(www\.)?', ''), '[?#].*$', ''), '/+$', ''), '');
$function$;
