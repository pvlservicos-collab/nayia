CREATE OR REPLACE FUNCTION public.condominio_google_chave(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nullif(btrim(regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '\s+', ' ', 'g')), '');
$function$;
