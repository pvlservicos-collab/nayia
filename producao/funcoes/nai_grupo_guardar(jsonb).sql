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
  SELECT x.tipo, x.texto, x.midia INTO v_tipo, v_texto, v_midia FROM (VALUES
      ('texto',     p->'text'->>'message',        NULL),
      ('imagem',    p->'image'->>'caption',       p->'image'->>'imageUrl'),
      ('video',     p->'video'->>'caption',       p->'video'->>'videoUrl'),
      ('audio',     NULL,                         p->'audio'->>'audioUrl'),
      ('documento', coalesce(p->'document'->>'caption', p->'document'->>'fileName'), p->'document'->>'documentUrl'),
      ('figurinha', NULL,                         p->'sticker'->>'stickerUrl')) x(tipo, texto, midia)
   WHERE p ? (CASE x.tipo WHEN 'texto' THEN 'text' WHEN 'imagem' THEN 'image' WHEN 'video' THEN 'video'
                          WHEN 'audio' THEN 'audio' WHEN 'documento' THEN 'document' ELSE 'sticker' END)
   LIMIT 1;
  v_quando := CASE WHEN coalesce(p->>'momment', '') ~ '^\d{12,14}$' THEN to_timestamp((p->>'momment')::bigint / 1000.0) ELSE now() END;
  INSERT INTO privado.grupo_conversa (message_id, grupo_id, grupo_nome, de_mim, remetente, remetente_nome,
                                      tipo, texto, midia_url, citado_id, enviada_em)
  VALUES (p->>'messageId', p->>'phone', nullif(btrim(coalesce(p->>'chatName', '')), ''),
          coalesce((p->>'fromMe')::boolean, false),
          nullif(regexp_replace(coalesce(p->>'participantPhone', ''), '\D', '', 'g'), ''),
          nullif(btrim(coalesce(p->>'senderName', '')), ''),
          coalesce(v_tipo, 'outro'), left(v_texto, 8000), v_midia, nullif(p->>'referenceMessageId', ''), v_quando)
  ON CONFLICT (message_id) DO NOTHING;
  RETURN FOUND;
EXCEPTION WHEN OTHERS THEN
  RETURN false;     -- guardar mensagem de grupo nunca derruba o fluxo que chamou
END;
$function$;
