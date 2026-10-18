CREATE OR REPLACE FUNCTION public.site_scrap_contatos_acao(p_ids bigint[], p_acao text, p_valor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int := 0; v_lista bigint; v_pulados int := 0;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'nenhum contato escolhido'); END IF;
  CASE p_acao
    WHEN 'status' THEN
      IF p_valor NOT IN ('novo', 'contatado', 'respondeu', 'interessado', 'descartado') THEN RETURN jsonb_build_object('ok', false, 'erro', 'status inválido'); END IF;
      UPDATE scrap_contato SET status = p_valor, atualizado_em = now() WHERE id = ANY (p_ids);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'etiqueta_por' THEN
      IF nullif(trim(p_valor), '') IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga a etiqueta'); END IF;
      UPDATE scrap_contato SET etiquetas = array_append(etiquetas, trim(p_valor)), atualizado_em = now()
       WHERE id = ANY (p_ids) AND NOT (trim(p_valor) = ANY (etiquetas));
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'etiqueta_tirar' THEN
      UPDATE scrap_contato SET etiquetas = array_remove(etiquetas, trim(p_valor)), atualizado_em = now()
       WHERE id = ANY (p_ids) AND trim(p_valor) = ANY (etiquetas);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'mover', 'copiar' THEN
      v_lista := nullif(p_valor, '')::bigint;
      IF v_lista IS NULL OR NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = v_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista de destino não existe'); END IF;
      INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, anunciante_id, confirmado, n_anuncios, bairros, preco_min, preco_max,
                                 exemplo_url, exemplo_titulo, status, etiquetas, observacao, dados)
      SELECT v_lista, telefone, nome, empresa, CASE WHEN origem = 'olx' THEN 'manual' ELSE origem END, anunciante_id, confirmado, n_anuncios, bairros,
             preco_min, preco_max, exemplo_url, exemplo_titulo, status, etiquetas, observacao, dados || jsonb_build_object('veio_da_lista', lista_id)
        FROM scrap_contato WHERE id = ANY (p_ids) AND lista_id <> v_lista
      ON CONFLICT (lista_id, telefone) DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_pulados := cardinality(p_ids) - v_n;
      IF p_acao = 'mover' THEN DELETE FROM scrap_contato WHERE id = ANY (p_ids) AND lista_id <> v_lista; END IF;
    WHEN 'apagar' THEN
      DELETE FROM scrap_contato WHERE id = ANY (p_ids);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSE
      RETURN jsonb_build_object('ok', false, 'erro', 'ação desconhecida: ' || coalesce(p_acao, ''));
  END CASE;
  RETURN jsonb_build_object('ok', true, 'n', v_n, 'pulados', v_pulados);
END
$function$;
