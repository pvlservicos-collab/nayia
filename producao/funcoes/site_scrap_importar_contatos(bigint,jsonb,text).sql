CREATE OR REPLACE FUNCTION public.site_scrap_importar_contatos(p_lista bigint, p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int; v_invalidos int; v_repetidos int; v_total int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = p_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  CREATE TEMP TABLE _entrada ON COMMIT DROP AS
    SELECT scrap_telefone_normalizar(x->>'telefone') AS telefone, nullif(trim(x->>'nome'), '') AS nome, nullif(trim(x->>'empresa'), '') AS empresa,
           nullif(trim(x->>'observacao'), '') AS observacao,
           coalesce((SELECT array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> '') FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(x->'etiquetas') = 'array' THEN x->'etiquetas' ELSE '[]'::jsonb END) e), '{}') AS etiquetas
      FROM jsonb_array_elements(coalesce(p, '[]'::jsonb)) x;
  SELECT count(*) INTO v_total FROM _entrada;
  SELECT count(*) INTO v_invalidos FROM _entrada WHERE telefone IS NULL;
  INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, observacao, etiquetas, dados)
  SELECT DISTINCT ON (telefone) p_lista, telefone, nome, empresa, 'csv', observacao, etiquetas, jsonb_build_object('criado_por', p_quem)
    FROM _entrada WHERE telefone IS NOT NULL ORDER BY telefone, nome NULLS LAST
  ON CONFLICT (lista_id, telefone) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_repetidos := v_total - v_invalidos - v_n;
  DROP TABLE _entrada;
  UPDATE scrap_lista SET atualizado_em = now() WHERE id = p_lista;
  RETURN jsonb_build_object('ok', true, 'inseridos', v_n, 'invalidos', v_invalidos, 'repetidos', v_repetidos);
END
$function$;
