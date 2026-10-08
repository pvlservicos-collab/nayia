CREATE OR REPLACE FUNCTION public.crm_olx_chat_receber(p_conta text, p_segredo text, p jsonb, p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_segredo text;
  v_chat_id text := nullif(btrim(coalesce(p ->> 'chatId', '')), '');
  v_msg_id  text := nullif(btrim(coalesce(p ->> 'messageId', '')), '');
  v_texto   text := coalesce(p ->> 'message', '');
  v_de      text;
  v_chat    bigint;
  v_n       integer;
BEGIN
  SELECT c.segredo INTO v_segredo FROM privado.olx_conta c WHERE c.conta = p_conta;
  IF v_segredo IS NULL OR p_segredo IS NULL OR length(p_segredo) < 40 OR v_segredo <> p_segredo THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'nao_autorizado');
  END IF;
  IF p IS NULL OR jsonb_typeof(p) <> 'object' OR v_chat_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'formato', 'erro', 'faltou o chatId');
  END IF;
  IF length(p::text) > 60000 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'grande_demais');
  END IF;
  -- sem messageId (não deveria): a mesma mensagem repetida dá o mesmo id
  v_msg_id := coalesce(v_msg_id, 'sem-id-' || md5(p::text));
  v_de := CASE WHEN lower(coalesce(p ->> 'senderType', '')) = 'system' THEN 'sistema'
               WHEN lower(coalesce(p ->> 'origin', '')) = 'seller' OR lower(coalesce(p ->> 'senderType', '')) = 'seller' THEN 'nos'
               ELSE 'comprador' END;

  INSERT INTO privado.olx_chat AS h (conta, chat_id, list_id, nome, email, telefone)
  VALUES (p_conta, v_chat_id, nullif(btrim(coalesce(p ->> 'listId', '')), ''),
          CASE WHEN v_de = 'comprador' THEN left(nullif(btrim(coalesce(p ->> 'name', '')), ''), 160) END,
          CASE WHEN v_de = 'comprador' THEN left(nullif(btrim(coalesce(p ->> 'email', '')), ''), 160) END,
          CASE WHEN v_de = 'comprador' THEN left(nullif(btrim(coalesce(p ->> 'phone', '')), ''), 40) END)
  ON CONFLICT (conta, chat_id) DO UPDATE
     SET list_id = coalesce(h.list_id, excluded.list_id),
         nome = coalesce(excluded.nome, h.nome),
         email = coalesce(excluded.email, h.email),
         telefone = coalesce(excluded.telefone, h.telefone),
         atualizado_em = now()
  RETURNING h.id INTO v_chat;

  INSERT INTO privado.olx_chat_mensagem (chat, message_id, de, texto, olx_timestamp, bruto, ip)
  VALUES (v_chat, left(v_msg_id, 200), v_de, v_texto, left(p ->> 'messageTimestamp', 60), p, left(p_ip, 60))
  ON CONFLICT (chat, message_id) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n > 0 THEN
    UPDATE privado.olx_chat
       SET ultima_em = now(), ultima_texto = left(v_texto, 300), ultima_de = v_de,
           nao_lidas = nao_lidas + CASE WHEN v_de = 'comprador' THEN 1 ELSE 0 END, atualizado_em = now()
     WHERE id = v_chat;
  END IF;
  RETURN jsonb_build_object('ok', true, 'novo', v_n > 0, 'chat', v_chat, 'de', v_de);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'codigo_erro', 'falha', 'erro', SQLERRM);
END
$function$;
