-- 277 (03/10/2026): O PAINEL DOS GRUPOS DA PARCERIA (CRM).
--
-- Pedro, 03/10: "preciso criar um painel com os grupos... ver, editar, mandar msg, ler, tirar dados, do
-- número parceria".
--
-- O que a Z-API deixa (medido em 03/10, só leitura): a lista dos 27 grupos, os dados de cada um
-- (participantes com telefone e quem é admin, descrição, configurações) e as ações de edição -- estas só
-- nos 5 grupos em que o número da Parceria é admin. Mandar mensagem, sim. O HISTÓRICO NÃO: o endpoint de
-- mensagens do chat responde "Does not work in multi device version". Ler o grupo só é possível guardando
-- o que chega pelo webhook a partir de agora.
--
-- Este arquivo dá ao CRM (papel nay_disparo, que só EXECUTA função) o que ele precisa do banco da Nay:
--   crm_grupos_conhecidos()          o que a casa sabe de cada grupo (disparo, grupo de corretores, mensagens guardadas)
--   crm_grupo_pessoas(telefones)     nome e "é corretor?" de cada participante (a Z-API só dá o telefone)
--   crm_grupo_mensagens(grupo, ...)  as mensagens guardadas do grupo, da mais nova para a mais velha
-- e a guarda das mensagens:
--   privado.grupo_conversa           toda mensagem de grupo que chegar (telefone de gente: schema privado)
--   nai_grupo_guardar(webhook)       grava a mensagem crua do webhook da Z-API; só grupo, uma vez cada
-- A guarda só começa quando o fluxo do n8n chamar nai_grupo_guardar (import de madrugada, à parte).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grupo_conversa (
  message_id     text PRIMARY KEY,
  grupo_id       text NOT NULL,
  grupo_nome     text,
  de_mim         boolean NOT NULL DEFAULT false,
  remetente      text,                         -- telefone de quem escreveu (só dígitos)
  remetente_nome text,
  tipo           text NOT NULL DEFAULT 'texto', -- texto | imagem | audio | video | documento | figurinha | outro
  texto          text,
  midia_url      text,
  citado_id      text,
  enviada_em     timestamptz NOT NULL DEFAULT now(),
  guardada_em    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_conversa_grupo ON privado.grupo_conversa (grupo_id, enviada_em DESC);
COMMENT ON TABLE privado.grupo_conversa IS
  '277: toda mensagem dos grupos do número da Parceria, guardada do webhook da Z-API (a Z-API não entrega histórico).';

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

COMMENT ON FUNCTION public.nai_grupo_guardar(jsonb) IS
  '277: guarda a mensagem de grupo do webhook da Z-API em privado.grupo_conversa. Não grupo, sem id ou repetida: false. Nunca levanta erro.';

CREATE OR REPLACE FUNCTION public.crm_grupos_conhecidos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH ids AS (
    SELECT id_grupo AS id FROM grupos
    UNION SELECT grupo_id FROM nai_grupo_corretor
    UNION SELECT DISTINCT grupo_id FROM privado.grupo_conversa
  )
  SELECT coalesce(jsonb_object_agg(ids.id, jsonb_strip_nulls(jsonb_build_object(
           'disparo', g.ativo, 'apelido', g.apelido, 'limite_dia', g.limite_dia,
           'aceita_venda', g.aceita_venda, 'aceita_locacao', g.aceita_locacao,
           'corretores', gc.incluir, 'membros_vistos', gc.membros,
           'mensagens', (SELECT count(*) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id),
           'ultima_mensagem', (SELECT max(m.enviada_em) FROM privado.grupo_conversa m WHERE m.grupo_id = ids.id)))), '{}'::jsonb)
    FROM ids
    LEFT JOIN grupos g ON g.id_grupo = ids.id
    LEFT JOIN nai_grupo_corretor gc ON gc.grupo_id = ids.id;
$function$;

CREATE OR REPLACE FUNCTION public.crm_grupo_pessoas(p_telefones text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH pedidos AS (
    SELECT DISTINCT t AS telefone, nai_chave(t) AS chave
      FROM unnest(coalesce(p_telefones, '{}'::text[])) t
     WHERE t ~ '^\d{10,15}$'
  ), cor AS (
    SELECT DISTINCT ON (nai_chave(c.telefone)) nai_chave(c.telefone) AS chave, nullif(btrim(c.nome), '') AS nome, c.ativo
      FROM corretores c
     WHERE nai_chave(c.telefone) IN (SELECT chave FROM pedidos)
     ORDER BY nai_chave(c.telefone), c.ativo DESC NULLS LAST
  )
  SELECT coalesce(jsonb_object_agg(p.telefone, jsonb_strip_nulls(jsonb_build_object(
           'nome', coalesce(cor.nome, nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), '')),
           'corretor', cor.chave IS NOT NULL,
           'falou_com_a_nay', k.id IS NOT NULL))), '{}'::jsonb)
    FROM pedidos p
    LEFT JOIN cor ON cor.chave = p.chave
    LEFT JOIN nai_contato k ON k.chave = p.chave;
$function$;

CREATE OR REPLACE FUNCTION public.crm_grupo_mensagens(p_grupo text, p_antes timestamptz DEFAULT NULL, p_limite integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'id', m.message_id, 'de_mim', m.de_mim, 'remetente', m.remetente, 'remetente_nome', m.remetente_nome,
           'tipo', m.tipo, 'texto', m.texto, 'midia_url', m.midia_url, 'citado_id', m.citado_id, 'quando', m.enviada_em))
           ORDER BY m.enviada_em DESC), '[]'::jsonb)
    FROM (SELECT * FROM privado.grupo_conversa
           WHERE grupo_id = p_grupo AND (p_antes IS NULL OR enviada_em < p_antes)
           ORDER BY enviada_em DESC
           LIMIT greatest(1, least(coalesce(p_limite, 60), 200))) m;
$function$;

REVOKE ALL ON FUNCTION public.nai_grupo_guardar(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_grupos_conhecidos() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_grupo_pessoas(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_grupo_mensagens(text, timestamptz, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_grupos_conhecidos() TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_grupo_pessoas(text[]) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_grupo_mensagens(text, timestamptz, integer) TO nay_disparo;

COMMIT;
