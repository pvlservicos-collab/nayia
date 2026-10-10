-- 337 -- Captação ativa: importar a conversa EXPORTADA do WhatsApp (os pedidos dos últimos 2 dias)
--
-- Pedro, 09/10/2026: "quero que teste com os últimos 2 dias de solicitações que tiveram em todos os grupos do
-- número de parceria".
--
-- Esses 2 dias não existem em sistema nenhum: a Z-API da Parceria só entrega avisos de grupo (entrou, saiu,
-- apagou), não devolve histórico ("Does not work in multi device version"), e a Evolution da VPS2 está com
-- "ignorar grupos" ligado. Conferido em 09/10 nas execuções do n8n, no CRM, no naydb e no banco da Evolution.
-- O histórico só existe no celular. O WhatsApp exporta a conversa do grupo em texto (grupo › Mais › Exportar
-- conversa › Sem mídia), e a aba passa a aceitar esse arquivo: o navegador lê o .txt (ou o .zip do iPhone),
-- manda as mensagens da janela para cá, e o leitor (nay-grupos) trata cada uma como mensagem de grupo.
--
--   privado.grupo_importada               as mensagens que vieram do arquivo (uma vez só cada)
--   site_captacao_grupos_importar         a rota da tela grava por aqui
--   site_captacao_grupos                  passa a dizer quantas foram importadas e quantas faltam ler
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grupo_importada (
  ref            text        PRIMARY KEY,         -- 'imp:' + resumo de grupo, hora, autor e texto: reimportar não repete
  grupo_nome     text        NOT NULL,
  remetente      text,                            -- telefone, quando o autor veio como número
  remetente_nome text,                            -- nome, quando o autor veio como nome
  enviada_em     timestamptz NOT NULL,
  texto          text        NOT NULL,
  importada_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_importada_quando ON privado.grupo_importada (enviada_em DESC);

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_importar(p_grupo text, p_mensagens jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_grupo text := left(regexp_replace(btrim(coalesce(p_grupo, '')), '\s+', ' ', 'g'), 120);
  v_horas int;
  v_total int; v_dentro int; v_novas int;
BEGIN
  IF v_grupo = '' THEN RETURN jsonb_build_object('erro', 'Diga de qual grupo é a conversa.'); END IF;
  IF p_mensagens IS NULL OR jsonb_typeof(p_mensagens) <> 'array' THEN
    RETURN jsonb_build_object('erro', 'Não recebi as mensagens da conversa.');
  END IF;
  IF jsonb_array_length(p_mensagens) > 2000 THEN
    RETURN jsonb_build_object('erro', 'Muitas mensagens de uma vez (o máximo é 2.000 por envio).');
  END IF;
  SELECT coalesce(nullif(e.config->>'janela_h', '')::int, 48) INTO v_horas FROM privado.grupo_captacao_estado e WHERE e.id = 1;
  v_horas := coalesce(v_horas, 48);

  WITH m AS (
    SELECT (x->>'quando')::timestamptz AS quando,
           nullif(btrim(coalesce(x->>'autor', '')), '') AS autor,
           btrim(coalesce(x->>'texto', '')) AS texto
      FROM jsonb_array_elements(p_mensagens) x
     WHERE coalesce(x->>'quando', '') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$'
       AND btrim(coalesce(x->>'texto', '')) <> ''
  ), d AS (
    SELECT * FROM m WHERE m.quando > now() - make_interval(hours => v_horas) AND m.quando < now() + interval '15 minutes'
  ), i AS (
    INSERT INTO privado.grupo_importada (ref, grupo_nome, remetente, remetente_nome, enviada_em, texto)
    SELECT DISTINCT ON (1)
           'imp:' || md5(v_grupo || '|' || d.quando::text || '|' || coalesce(d.autor, '') || '|' || d.texto),
           v_grupo,
           -- o autor é um telefone ("+55 92 98888-7777") ou o nome salvo no celular de quem exportou
           CASE WHEN d.autor !~ '[A-Za-zÀ-ÿ]' AND regexp_replace(d.autor, '\D', '', 'g') ~ '^\d{10,13}$'
                THEN regexp_replace(d.autor, '\D', '', 'g') END,
           CASE WHEN d.autor ~ '[A-Za-zÀ-ÿ]' THEN left(regexp_replace(d.autor, '^~\s*', ''), 80) END,
           d.quando, left(d.texto, 8000)
      FROM d
    ON CONFLICT (ref) DO NOTHING
    RETURNING 1
  )
  SELECT (SELECT count(*) FROM m), (SELECT count(*) FROM d), (SELECT count(*) FROM i) INTO v_total, v_dentro, v_novas;

  RETURN jsonb_build_object('ok', true, 'grupo', v_grupo, 'recebidas', v_total, 'na_janela', v_dentro, 'novas', v_novas,
                            'repetidas', v_dentro - v_novas, 'horas', v_horas);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('erro', 'Não consegui ler as mensagens desse arquivo.');
END
$function$;

REVOKE ALL ON FUNCTION public.site_captacao_grupos_importar(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos_importar(text, jsonb) TO nay_site_escrita;

-- A tela passa a saber do que foi importado e do que ainda falta o leitor ler
DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.site_captacao_grupos(text,integer,integer)'::regprocedure);
  v_velho text := $v$    INTO v_fonte FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim;$v$;
  v_novo  text := $n$    INTO v_fonte FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim;

  -- 337: o que veio de conversa exportada, e o que ainda está na fila do leitor (grupo, importada e teste)
  v_fonte := v_fonte || jsonb_build_object(
    'importadas', (SELECT count(*) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde),
    'grupos_importados', (SELECT count(DISTINCT g.grupo_nome) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde),
    'na_fila', (SELECT count(*) FROM privado.grupo_importada g WHERE g.enviada_em >= v_desde
                   AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = g.ref))
             + (SELECT count(*) FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim
                   AND nullif(btrim(c.texto), '') IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.ref = c.message_id))
             + (SELECT count(*) FROM privado.grupo_pedido_teste t
                 WHERE NOT EXISTS (SELECT 1 FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'teste' AND l.ref = t.id::text)),
    'nao_eram_pedido', (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde
                           AND l.pedidos = 0 AND l.erro IS NULL),
    'com_erro', (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde AND l.erro IS NOT NULL));$n$;
BEGIN
  IF position('grupo_importada' IN v_def) > 0 THEN RAISE EXCEPTION '337: já aplicada'; END IF;
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '337: o trecho de site_captacao_grupos mudou no banco; leia a função viva antes';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

COMMIT;
