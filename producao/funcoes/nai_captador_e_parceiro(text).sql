CREATE OR REPLACE FUNCTION public.nai_captador_e_parceiro(p_captador text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_captador, '') ~* '\(\s*parceir[oa]s?\s*\)'
$function$;
