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
