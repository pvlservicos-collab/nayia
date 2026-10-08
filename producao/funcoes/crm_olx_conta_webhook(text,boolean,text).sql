CREATE OR REPLACE FUNCTION public.crm_olx_conta_webhook(p_conta text, p_ativo boolean, p_resposta text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_conta
     SET webhook_ativado_em = CASE WHEN p_ativo THEN now() END,
         webhook_resposta = left(p_resposta, 300), atualizado_em = now()
   WHERE conta = p_conta;
  RETURN FOUND;
END
$function$;
