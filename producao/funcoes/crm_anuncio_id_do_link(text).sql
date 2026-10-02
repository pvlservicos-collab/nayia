CREATE OR REPLACE FUNCTION public.crm_anuncio_id_do_link(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT (regexp_match(crm_anuncio_link_normal(p), '([0-9]{6,})[^0-9]*$'))[1];
$function$;
