-- 314 (08/10/2026): O CHAT DA OLX DENTRO DO CRM.
-- Pedro: "quero implementar o chat da olx, serão 2 contas, esse chat olx vai ser 2
-- abas, aba Conta proprietários e aba Conta corretores ... basicamente quero
-- responder o chat da olx pelo meu crm, enviar e receber mensagens pelo crm".
--
-- A OLX tem uma integração oficial de chat (crm/docs/olx/chat-da-olx.md): cada
-- conta autoriza o nosso aplicativo (OAuth, escopo `chat`), nós ligamos um webhook
-- com o token dela, a OLX passa a chamar esse webhook a cada mensagem e nós
-- respondemos por POST /autoservice/v1/chat/send.
--
-- O QUE ESTA MIGRAÇÃO CRIA (tudo no schema `privado`: tem nome, e-mail e telefone
-- de quem escreve, e o token de cada conta; o CRM só entra pelas funções):
--   privado.olx_conta           uma linha por conta: o segredo do webhook, o token
--   privado.olx_chat            uma conversa (conta + chatId da OLX)
--   privado.olx_chat_mensagem   cada mensagem, de quem veio, e o que a OLX mandou
--
-- A OLX NÃO ASSINA A CHAMADA DO WEBHOOK. Quem prova que é ela é o SEGREDO que vai
-- no caminho do endereço que nós mesmos registramos (um por conta); o IP de onde
-- veio fica gravado em cada mensagem (o dela é 54.162.151.93).
--
-- A MESMA MENSAGEM NÃO ENTRA DUAS VEZES: (conversa, messageId) é único. A que nós
-- mandamos é gravada com o messageId que geramos; se a OLX devolver o eco pelo
-- webhook, ele cai na mesma linha.
--
-- DE QUEM É A MENSAGEM: `origin = seller` é nossa; `senderType = system` é do
-- sistema; o resto é do comprador. Nome, e-mail e telefone só são guardados da
-- mensagem do comprador (na nossa, esses campos são os da nossa conta).
--
-- A HORA: `messageTimestamp` vem sem fuso; fica guardado como veio e a conversa
-- usa a hora em que a mensagem chegou a nós.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.olx_conta (
  conta              text PRIMARY KEY CHECK (conta IN ('proprietarios', 'corretores')),
  segredo            text NOT NULL,
  access_token       text,
  conectada_em       timestamptz,
  conectada_por      text,
  olx_nome           text,
  olx_email          text,
  webhook_ativado_em timestamptz,
  webhook_resposta   text,
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.olx_conta IS '314: as contas da OLX ligadas ao CRM (proprietarios, corretores): segredo do webhook e token';

CREATE TABLE IF NOT EXISTS privado.olx_chat (
  id            bigserial PRIMARY KEY,
  conta         text NOT NULL REFERENCES privado.olx_conta (conta),
  chat_id       text NOT NULL,
  list_id       text,
  nome          text,
  email         text,
  telefone      text,
  ultima_em     timestamptz,
  ultima_texto  text,
  ultima_de     text,
  nao_lidas     integer NOT NULL DEFAULT 0,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  UNIQUE (conta, chat_id)
);
CREATE INDEX IF NOT EXISTS olx_chat_lista ON privado.olx_chat (conta, ultima_em DESC);
COMMENT ON TABLE privado.olx_chat IS '314: cada conversa do chat da OLX (conta + chatId)';

CREATE TABLE IF NOT EXISTS privado.olx_chat_mensagem (
  id            bigserial PRIMARY KEY,
  chat          bigint NOT NULL REFERENCES privado.olx_chat (id),
  message_id    text NOT NULL,
  de            text NOT NULL CHECK (de IN ('comprador', 'nos', 'sistema')),
  texto         text NOT NULL DEFAULT '',
  quando        timestamptz NOT NULL DEFAULT now(),
  olx_timestamp text,
  enviada_por   text,
  bruto         jsonb,
  ip            text,
  UNIQUE (chat, message_id)
);
CREATE INDEX IF NOT EXISTS olx_chat_mensagem_ordem ON privado.olx_chat_mensagem (chat, id);
COMMENT ON TABLE privado.olx_chat_mensagem IS '314: as mensagens de cada conversa da OLX; `nos` = a nossa conta, `comprador` = quem escreveu';

-- 1. A CONTA --------------------------------------------------------------------
-- Garante a linha da conta com um segredo (gerado no CRM) e devolve o que vale.
CREATE OR REPLACE FUNCTION public.crm_olx_conta_preparar(p_conta text, p_segredo text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v text;
BEGIN
  IF p_conta NOT IN ('proprietarios', 'corretores') THEN RETURN NULL; END IF;
  IF p_segredo IS NULL OR p_segredo !~ '^[A-Za-z0-9]{40,100}$' THEN RETURN NULL; END IF;
  INSERT INTO privado.olx_conta (conta, segredo) VALUES (p_conta, p_segredo) ON CONFLICT (conta) DO NOTHING;
  SELECT c.segredo INTO v FROM privado.olx_conta c WHERE c.conta = p_conta;
  RETURN v;
END
$function$;

-- O estado da conta para a tela: nada de segredo nem de token.
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

-- A autorização deu certo: guarda o token e quem é a conta na OLX.
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

-- O resultado de ligar (ou desligar) o webhook na OLX.
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

-- O token, para o CRM chamar a OLX (mandar mensagem, ligar o webhook).
CREATE OR REPLACE FUNCTION public.crm_olx_conta_token(p_conta text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.access_token FROM privado.olx_conta c WHERE c.conta = p_conta;
$function$;

-- 2. A MENSAGEM QUE CHEGA DA OLX --------------------------------------------------
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

-- 3. A TELA -----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_olx_chats(p_conta text, p_limite integer DEFAULT 300)
 RETURNS TABLE(id bigint, chat_id text, list_id text, nome text, email text, telefone text, ultima_em timestamptz,
               ultima_texto text, ultima_de text, nao_lidas integer, criado_em timestamptz, mensagens bigint)
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

CREATE OR REPLACE FUNCTION public.crm_olx_chat_mensagens(p_conta text, p_chat bigint)
 RETURNS TABLE(id bigint, message_id text, de text, texto text, quando timestamptz, enviada_por text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.id, m.message_id, m.de, m.texto, m.quando, m.enviada_por
    FROM privado.olx_chat_mensagem m JOIN privado.olx_chat h ON h.id = m.chat
   WHERE h.conta = p_conta AND h.id = p_chat
   ORDER BY m.id
   LIMIT 2000
$function$;

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

-- O chatId da OLX de uma conversa nossa (para mandar a resposta).
CREATE OR REPLACE FUNCTION public.crm_olx_chat_id_da_olx(p_conta text, p_chat bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT h.chat_id FROM privado.olx_chat h WHERE h.conta = p_conta AND h.id = p_chat;
$function$;

-- A mensagem que NÓS mandamos e a OLX aceitou.
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

DO $do$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'crm_olx_conta_preparar(text,text)', 'crm_olx_conta_estado(text)', 'crm_olx_conta_conectar(text,text,text,text,text)',
    'crm_olx_conta_webhook(text,boolean,text)', 'crm_olx_conta_token(text)', 'crm_olx_chat_receber(text,text,jsonb,text)',
    'crm_olx_chats(text,integer)', 'crm_olx_chat_mensagens(text,bigint)', 'crm_olx_chat_lido(text,bigint)',
    'crm_olx_chat_id_da_olx(text,bigint)', 'crm_olx_chat_enviada(text,bigint,text,text,text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO nay_disparo', f);
  END LOOP;
END
$do$;
COMMIT;
