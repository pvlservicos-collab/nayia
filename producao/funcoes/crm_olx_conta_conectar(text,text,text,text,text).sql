CREATE OR REPLACE FUNCTION public.crm_olx_conta_conectar(p_conta text, p_token text, p_quem text, p_nome text, p_email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF coalesce(btrim(p_token), '') = '' THEN RETURN false; END IF;
  UPDATE privado.olx_conta
     SET access_token = btrim(p_token), conectada_em = now(), conectada_por = left(nullif(btrim(p_quem), ''), 120),
         olx_nome = left(nullif(btrim(p_nome), ''), 160), olx_email = left(nullif(btrim(p_email), ''), 160),
         webhook_ativado_em = NULL, webhook_resposta = NULL, atualizado_em = now()
   WHERE conta = p_conta;
  RETURN FOUND;
END
$function$;
