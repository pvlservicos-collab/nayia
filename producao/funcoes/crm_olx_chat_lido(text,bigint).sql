CREATE OR REPLACE FUNCTION public.crm_olx_chat_lido(p_conta text, p_chat bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_chat SET nao_lidas = 0 WHERE conta = p_conta AND id = p_chat AND nao_lidas <> 0;
  RETURN FOUND;
END
$function$;
