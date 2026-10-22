CREATE OR REPLACE FUNCTION public.ia_modelo_do_no(p_no text, p_padrao text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((SELECT nullif(btrim(m.modelo), '') FROM privado.ia_no_modelo m WHERE m.no = p_no), p_padrao)
$function$;
