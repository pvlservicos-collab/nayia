CREATE OR REPLACE FUNCTION public.site_scrap_contato_salvar(p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_tel text; v_lista bigint := nullif(p->>'lista_id', '')::bigint; v_et text[]; v_aviso text;
BEGIN
  IF p ? 'etiquetas' THEN
    SELECT coalesce(array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> ''), '{}') INTO v_et FROM jsonb_array_elements_text(coalesce(p->'etiquetas', '[]'::jsonb)) e;
  END IF;
  IF v_id IS NULL THEN
    v_tel := scrap_telefone_normalizar(p->>'telefone');
    IF v_tel IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'telefone inválido'); END IF;
    IF v_lista IS NULL OR NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = v_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'escolha a lista'); END IF;
    IF EXISTS (SELECT 1 FROM scrap_contato WHERE lista_id = v_lista AND telefone = v_tel) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'esse telefone já está nesta lista', 'telefone', scrap_telefone_formatar(v_tel));
    END IF;
    IF scrap_bloqueado(v_tel) AND (SELECT tipo FROM scrap_lista WHERE id = v_lista) = 'lista' THEN v_aviso := 'esse número está na blacklist (falamos há pouco); entrou mesmo assim'; END IF;
    INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, status, etiquetas, observacao, dados)
    VALUES (v_lista, v_tel, nullif(trim(p->>'nome'), ''), nullif(trim(p->>'empresa'), ''), 'manual',
            coalesce(nullif(p->>'status', ''), 'novo'), coalesce(v_et, '{}'), nullif(trim(p->>'observacao'), ''),
            jsonb_build_object('criado_por', p_quem))
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id, 'criado', true, 'aviso', v_aviso);
  END IF;
  IF p ? 'telefone' THEN
    v_tel := scrap_telefone_normalizar(p->>'telefone');
    IF v_tel IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'telefone inválido'); END IF;
    IF EXISTS (SELECT 1 FROM scrap_contato c WHERE c.telefone = v_tel AND c.id <> v_id AND c.lista_id = (SELECT lista_id FROM scrap_contato WHERE id = v_id)) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'esse telefone já está nesta lista');
    END IF;
  END IF;
  UPDATE scrap_contato SET
    nome = CASE WHEN p ? 'nome' THEN nullif(trim(p->>'nome'), '') ELSE nome END,
    telefone = coalesce(v_tel, telefone),
    empresa = CASE WHEN p ? 'empresa' THEN nullif(trim(p->>'empresa'), '') ELSE empresa END,
    status = CASE WHEN p ? 'status' THEN coalesce(nullif(p->>'status', ''), status) ELSE status END,
    etiquetas = coalesce(v_et, etiquetas),
    observacao = CASE WHEN p ? 'observacao' THEN nullif(trim(p->>'observacao'), '') ELSE observacao END,
    origem = CASE WHEN p ? 'nome' AND origem IN ('olx', 'sistema') THEN 'manual' ELSE origem END,
    atualizado_em = now()
   WHERE id = v_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'contato não existe'); END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;
