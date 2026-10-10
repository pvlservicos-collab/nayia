-- 338 -- A aba Grupos do CRM guarda MENSAGEM de grupo (e não aviso), e os grupos de id antigo deixam de ser descartados
--
-- Pedro, 09/10/2026: "mas eu tinha pedido para construir uma aba Grupos no CRM justamente para monitorar isso;
-- ela tá até bugada".
--
-- O que estava errado, medido em 09/10:
--   1. Desde 03/10 a tabela `privado.grupo_conversa` só recebeu AVISOS (apagou, entrou, saiu): 238 linhas, todas
--      tipo 'outro', sem texto. A aba desenha cada uma como um balão escrito "Mensagem" -- é o "bugada".
--      `nai_grupo_guardar` guardava qualquer evento com isGroup, inclusive aviso, reação e "aguardando mensagem"
--      (que ainda por cima ocupava o id e barrava a mensagem de verdade quando ela chegasse).
--   2. 13 dos 28 grupos têm o id no formato ANTIGO ("5592...-1600000000", sem "-group"). O roteador
--      (`nai_quem_atende`) só mandava ao espelho do CRM o que terminava em "-group": metade dos grupos era
--      descartada antes de chegar.
--   3. O texto das mensagens de grupo não sai da Z-API (o filtro do webhook "Ao receber"): isso se liga lá,
--      não aqui.
--
-- O que muda:
--   - `nai_grupo_guardar` só guarda MENSAGEM: texto, foto, vídeo, áudio, documento, figurinha, enquete, contato
--     e localização. Aviso, reação e evento sem conteúdo não entram (e não ocupam o id).
--   - `crm_grupo_mensagens` e `crm_grupos_conhecidos` não mostram nem contam as linhas vazias que já ficaram.
--   - `nai_quem_atende` reconhece os dois formatos de id de grupo.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_grupo_guardar(p jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_tipo text; v_texto text; v_midia text; v_quando timestamptz;
BEGIN
  IF p IS NULL OR NOT coalesce((p->>'isGroup')::boolean, false)
     OR coalesce(btrim(p->>'messageId'), '') = '' OR coalesce(btrim(p->>'phone'), '') = '' THEN
    RETURN false;
  END IF;
  -- 338: AVISO (entrou, saiu, apagou), REAÇÃO e "aguardando mensagem" não são mensagem. Não entram: viravam balão
  -- vazio na aba, e o "aguardando" ocupava o id e barrava a mensagem de verdade que vinha depois.
  IF nullif(btrim(coalesce(p->>'notification', '')), '') IS NOT NULL
     OR jsonb_typeof(p->'reaction') = 'object'
     OR coalesce((p->>'waitingMessage')::boolean, false) THEN
    RETURN false;
  END IF;
  SELECT x.tipo, x.texto, x.midia INTO v_tipo, v_texto, v_midia FROM (VALUES
      ('texto',     'text',     p->'text'->>'message',        NULL),
      ('imagem',    'image',    p->'image'->>'caption',       p->'image'->>'imageUrl'),
      ('video',     'video',    p->'video'->>'caption',       p->'video'->>'videoUrl'),
      ('audio',     'audio',    NULL,                         p->'audio'->>'audioUrl'),
      ('documento', 'document', coalesce(p->'document'->>'caption', p->'document'->>'fileName'), p->'document'->>'documentUrl'),
      ('figurinha', 'sticker',  NULL,                         p->'sticker'->>'stickerUrl'),
      -- o que a aba não tem desenho próprio entra como texto, dizendo o que é
      ('texto',     'poll',     '📊 Enquete: ' || coalesce(p->'poll'->>'question', ''), NULL),
      ('texto',     'contact',  '👤 Contato: ' || coalesce(p->'contact'->>'displayName', ''), NULL),
      ('texto',     'location', '📍 Localização: ' || coalesce(nullif(p->'location'->>'name', ''), p->'location'->>'address', ''), NULL)
    ) x(tipo, chave, texto, midia)
   WHERE jsonb_typeof(p->x.chave) = 'object'
   LIMIT 1;
  -- nada que a gente saiba ler: não guarda linha vazia
  IF v_tipo IS NULL OR (v_tipo = 'texto' AND nullif(btrim(coalesce(v_texto, '')), '') IS NULL) THEN
    RETURN false;
  END IF;
  v_quando := CASE WHEN coalesce(p->>'momment', '') ~ '^\d{12,14}$' THEN to_timestamp((p->>'momment')::bigint / 1000.0) ELSE now() END;
  INSERT INTO privado.grupo_conversa (message_id, grupo_id, grupo_nome, de_mim, remetente, remetente_nome,
                                      tipo, texto, midia_url, citado_id, enviada_em)
  VALUES (p->>'messageId', p->>'phone', nullif(btrim(coalesce(p->>'chatName', '')), ''),
          coalesce((p->>'fromMe')::boolean, false),
          nullif(regexp_replace(coalesce(p->>'participantPhone', ''), '\D', '', 'g'), ''),
          nullif(btrim(coalesce(p->>'senderName', '')), ''),
          v_tipo, left(v_texto, 8000), v_midia, nullif(p->>'referenceMessageId', ''), v_quando)
  -- a linha vazia que um evento antigo deixou com este id dá lugar à mensagem de verdade
  ON CONFLICT (message_id) DO UPDATE
     SET tipo = excluded.tipo, texto = excluded.texto, midia_url = excluded.midia_url, grupo_nome = excluded.grupo_nome,
         remetente = excluded.remetente, remetente_nome = excluded.remetente_nome, de_mim = excluded.de_mim,
         citado_id = excluded.citado_id, enviada_em = excluded.enviada_em
   WHERE privado.grupo_conversa.tipo = 'outro' AND privado.grupo_conversa.texto IS NULL AND privado.grupo_conversa.midia_url IS NULL;
  RETURN FOUND;
EXCEPTION WHEN OTHERS THEN
  RETURN false;     -- guardar mensagem de grupo nunca derruba o fluxo que chamou
END;
$function$;

-- a aba não mostra nem conta as linhas vazias que já ficaram guardadas (aviso guardado como mensagem)
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.crm_grupo_mensagens(text,timestamp with time zone,integer)'::regprocedure);
  v_velho text := $v$           WHERE grupo_id = p_grupo AND (p_antes IS NULL OR enviada_em < p_antes)$v$;
  v_novo  text := $n$           WHERE grupo_id = p_grupo AND (p_antes IS NULL OR enviada_em < p_antes)
             AND NOT (tipo = 'outro' AND texto IS NULL AND midia_url IS NULL)   -- 338: evento sem conteúdo não é mensagem$n$;
BEGIN
  IF position('338' IN v_def) > 0 THEN RAISE EXCEPTION '338: crm_grupo_mensagens já remendada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '338: o trecho de crm_grupo_mensagens mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

DO $mig$
DECLARE
  v_def text := pg_get_functiondef('public.crm_grupos_conhecidos()'::regprocedure);
  v_a1  text := $v$(SELECT count(*) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id)$v$;
  v_n1  text := $n$(SELECT count(*) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id
                                   AND NOT (m.tipo = 'outro' AND m.texto IS NULL AND m.midia_url IS NULL))$n$;
  v_a2  text := $v$(SELECT max(m.enviada_em) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id)$v$;
  v_n2  text := $n$(SELECT max(m.enviada_em) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id
                                   AND NOT (m.tipo = 'outro' AND m.texto IS NULL AND m.midia_url IS NULL))$n$;
BEGIN
  IF position('m.midia_url IS NULL' IN v_def) > 0 THEN RAISE EXCEPTION '338: crm_grupos_conhecidos já remendada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
     OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '338: os trechos de crm_grupos_conhecidos mudaram no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(replace(v_def, v_a1, v_n1), v_a2, v_n2);
END
$mig$;

-- o roteador: grupo de id antigo também vai ao espelho do CRM (o fluxo da NAI continua descartando grupo: ninguém responde)
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.nai_quem_atende(text,boolean,text)'::regprocedure);
  v_velho text := $v$  IF coalesce(p_grupo, false) AND coalesce(p_phone, '') ~ '-group$' THEN$v$;
  v_novo  text := $n$  -- 338: os DOIS formatos de id de grupo: "1203...-group" e o antigo "5592...-1600000000" (13 dos 28 grupos)
  IF coalesce(p_grupo, false) AND coalesce(p_phone, '') ~ '(-group$|^[0-9]{10,15}-[0-9]{8,12}$)' THEN$n$;
BEGIN
  IF position('338' IN v_def) > 0 THEN RAISE EXCEPTION '338: nai_quem_atende já remendada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '338: o trecho de nai_quem_atende mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

COMMIT;
