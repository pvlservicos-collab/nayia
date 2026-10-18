CREATE OR REPLACE FUNCTION public.site_scrap_lista_salvar(p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_nome text := nullif(trim(p->>'nome'), '');
BEGIN
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de um nome'); END IF;
  IF v_id IS NULL THEN
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por)
    VALUES (v_nome, nullif(trim(p->>'descricao'), ''), coalesce(nullif(p->>'origem', ''), 'manual'), nullif(trim(p->>'url_busca'), ''),
            coalesce(nullif(p->>'cor', ''), '#6d28d9'), coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem)
    RETURNING id INTO v_id;
  ELSE
    UPDATE scrap_lista SET nome = v_nome, descricao = coalesce(nullif(trim(p->>'descricao'), ''), descricao),
           url_busca = coalesce(nullif(trim(p->>'url_busca'), ''), url_busca), cor = coalesce(nullif(p->>'cor', ''), cor),
           ordem = coalesce((p->>'ordem')::int, ordem), atualizado_em = now()
     WHERE id = v_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;
