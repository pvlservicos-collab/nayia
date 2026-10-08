CREATE OR REPLACE FUNCTION public.crm_olx_conta_estado(p_conta text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((
    SELECT jsonb_build_object('conta', c.conta, 'conectada', c.access_token IS NOT NULL,
             'conectada_em', c.conectada_em, 'conectada_por', c.conectada_por,
             'olx_nome', c.olx_nome, 'olx_email', c.olx_email,
             'webhook_ativo', c.webhook_ativado_em IS NOT NULL, 'webhook_ativado_em', c.webhook_ativado_em,
             'webhook_resposta', c.webhook_resposta,
             'conversas', (SELECT count(*) FROM privado.olx_chat h WHERE h.conta = c.conta),
             'ultima_mensagem_em', (SELECT max(h.ultima_em) FROM privado.olx_chat h WHERE h.conta = c.conta))
      FROM privado.olx_conta c WHERE c.conta = p_conta),
    jsonb_build_object('conta', p_conta, 'conectada', false, 'webhook_ativo', false, 'conversas', 0));
$function$;
