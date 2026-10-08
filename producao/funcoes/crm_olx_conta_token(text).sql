CREATE OR REPLACE FUNCTION public.crm_olx_conta_token(p_conta text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.access_token FROM privado.olx_conta c WHERE c.conta = p_conta;
$function$;
