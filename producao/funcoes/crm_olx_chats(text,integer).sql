CREATE OR REPLACE FUNCTION public.crm_olx_chats(p_conta text, p_limite integer DEFAULT 300)
 RETURNS TABLE(id bigint, chat_id text, list_id text, nome text, email text, telefone text, ultima_em timestamp with time zone, ultima_texto text, ultima_de text, nao_lidas integer, criado_em timestamp with time zone, mensagens bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT h.id, h.chat_id, h.list_id, h.nome, h.email, h.telefone, h.ultima_em, h.ultima_texto, h.ultima_de,
         h.nao_lidas, h.criado_em, (SELECT count(*) FROM privado.olx_chat_mensagem m WHERE m.chat = h.id)
    FROM privado.olx_chat h
   WHERE h.conta = p_conta
   ORDER BY coalesce(h.ultima_em, h.criado_em) DESC, h.id DESC
   LIMIT least(greatest(coalesce(p_limite, 300), 1), 1000)
$function$;
