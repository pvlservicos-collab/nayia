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
           -- o autor é um telefone ("+55 [telefone …7777]") ou o nome salvo no celular de quem exportou
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
