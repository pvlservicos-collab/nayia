CREATE OR REPLACE FUNCTION public.site_whats_modelo_nota_salvar(p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_nome text := nullif(trim(p->>'nome'), ''); v_idioma text := coalesce(nullif(trim(p->>'idioma'), ''), 'pt_BR'); v_et text[];
BEGIN
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'sem o nome do modelo'); END IF;
  IF p ? 'etiquetas' THEN
    SELECT coalesce(array_agg(DISTINCT trim(e) ORDER BY trim(e)) FILTER (WHERE trim(e) <> ''), '{}') INTO v_et
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'etiquetas') = 'array' THEN p->'etiquetas' ELSE '[]'::jsonb END) e;
  END IF;
  INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, observacao, atualizado_por)
  VALUES (v_nome, v_idioma, coalesce(v_et, '{}'), nullif(trim(p->>'observacao'), ''), p_quem)
  ON CONFLICT (nome, idioma) DO UPDATE SET
    etiquetas = coalesce(v_et, whats_modelo_nota.etiquetas),
    observacao = CASE WHEN p ? 'observacao' THEN nullif(trim(p->>'observacao'), '') ELSE whats_modelo_nota.observacao END,
    atualizado_por = p_quem, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'nome', v_nome, 'idioma', v_idioma,
    'etiquetas', (SELECT to_jsonb(etiquetas) FROM whats_modelo_nota WHERE nome = v_nome AND idioma = v_idioma));
END
$function$;
