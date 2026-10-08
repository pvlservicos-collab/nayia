CREATE OR REPLACE FUNCTION public.crm_olx_chat_enviada(p_conta text, p_chat bigint, p_message_id text, p_texto text, p_quem text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM privado.olx_chat h WHERE h.conta = p_conta AND h.id = p_chat) THEN RETURN false; END IF;
  INSERT INTO privado.olx_chat_mensagem AS m (chat, message_id, de, texto, enviada_por)
  VALUES (p_chat, left(p_message_id, 200), 'nos', coalesce(p_texto, ''), left(nullif(btrim(p_quem), ''), 120))
  ON CONFLICT (chat, message_id) DO UPDATE SET enviada_por = coalesce(m.enviada_por, excluded.enviada_por);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE privado.olx_chat
     SET ultima_em = now(), ultima_texto = left(coalesce(p_texto, ''), 300), ultima_de = 'nos', nao_lidas = 0, atualizado_em = now()
   WHERE id = p_chat;
  RETURN v_n > 0;
END
$function$;
