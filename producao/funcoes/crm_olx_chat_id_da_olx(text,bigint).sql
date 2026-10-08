CREATE OR REPLACE FUNCTION public.crm_olx_chat_id_da_olx(p_conta text, p_chat bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT h.chat_id FROM privado.olx_chat h WHERE h.conta = p_conta AND h.id = p_chat;
$function$;
