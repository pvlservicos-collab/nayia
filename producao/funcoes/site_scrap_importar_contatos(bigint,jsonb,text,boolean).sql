CREATE OR REPLACE FUNCTION public.site_scrap_importar_contatos(p_lista bigint, p jsonb, p_quem text DEFAULT NULL::text, p_ignorar_blacklist boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int; v_invalidos int; v_repetidos int; v_total int; v_bloq int := 0; v_tipo text; v_origem text;
BEGIN
  SELECT tipo INTO v_tipo FROM scrap_lista WHERE id = p_lista;
  IF v_tipo IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  v_origem := coalesce(nullif(p->0->>'_origem', ''), 'csv');
  CREATE TEMP TABLE _entrada ON COMMIT DROP AS
    SELECT scrap_telefone_normalizar(x->>'telefone') AS telefone, nullif(trim(x->>'nome'), '') AS nome, nullif(trim(x->>'empresa'), '') AS empresa,
           nullif(trim(x->>'observacao'), '') AS observacao,
           coalesce((SELECT array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> '') FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(x->'etiquetas') = 'array' THEN x->'etiquetas' ELSE '[]'::jsonb END) e), '{}') AS etiquetas,
           CASE WHEN jsonb_typeof(x->'dados') = 'object' THEN x->'dados' ELSE '{}'::jsonb END AS dados
      FROM jsonb_array_elements(coalesce(p, '[]'::jsonb)) x;
  SELECT count(*) INTO v_total FROM _entrada;
  SELECT count(*) INTO v_invalidos FROM _entrada WHERE telefone IS NULL;
  IF v_tipo = 'lista' AND NOT p_ignorar_blacklist THEN
    DELETE FROM _entrada WHERE telefone IS NOT NULL AND scrap_bloqueado(telefone);
    GET DIAGNOSTICS v_bloq = ROW_COUNT;
  END IF;
  INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, observacao, etiquetas, dados)
  SELECT DISTINCT ON (telefone) p_lista, telefone, nome, empresa, CASE WHEN v_origem IN ('olx', 'manual', 'csv', 'sistema') THEN v_origem ELSE 'csv' END,
         observacao, etiquetas, dados || jsonb_build_object('criado_por', p_quem)
    FROM _entrada WHERE telefone IS NOT NULL ORDER BY telefone, nome NULLS LAST
  ON CONFLICT (lista_id, telefone) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_repetidos := v_total - v_invalidos - v_bloq - v_n;
  DROP TABLE _entrada;
  UPDATE scrap_lista SET atualizado_em = now(), bloqueados = bloqueados + v_bloq WHERE id = p_lista;
  RETURN jsonb_build_object('ok', true, 'inseridos', v_n, 'invalidos', v_invalidos, 'repetidos', v_repetidos, 'bloqueados', v_bloq);
END
$function$;
