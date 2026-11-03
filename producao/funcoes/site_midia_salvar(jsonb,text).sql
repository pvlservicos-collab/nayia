CREATE OR REPLACE FUNCTION public.site_midia_salvar(p jsonb, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_dem bigint := nullif(p->>'demanda_id', '')::bigint;
BEGIN
  IF coalesce(btrim(p->>'titulo'), '') = '' THEN RAISE EXCEPTION 'falta o título'; END IF;
  IF v_dem IS NOT NULL AND NOT EXISTS (SELECT 1 FROM midia_item WHERE id = v_dem AND tipo = 'demanda' AND excluido_em IS NULL) THEN
    v_dem := NULL;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO midia_item (canal, tipo, titulo, descricao, formato, quem, status, prioridade, data, demanda_id, origem, link, atualizado_por)
    VALUES (p->>'canal', coalesce(nullif(p->>'tipo', ''), 'demanda'), btrim(p->>'titulo'), nullif(btrim(p->>'descricao'), ''),
            nullif(btrim(p->>'formato'), ''), nullif(btrim(p->>'quem'), ''), coalesce(nullif(p->>'status', ''), 'ideia'),
            nullif(p->>'prioridade', ''), nullif(p->>'data', '')::date, v_dem, coalesce(nullif(p->>'origem', ''), 'tela'),
            nullif(btrim(p->>'link'), ''), left(p_quem, 80))
    RETURNING id INTO v_id;
  ELSE
    UPDATE midia_item SET canal = p->>'canal', tipo = coalesce(nullif(p->>'tipo', ''), tipo), titulo = btrim(p->>'titulo'),
           descricao = nullif(btrim(p->>'descricao'), ''), formato = nullif(btrim(p->>'formato'), ''),
           quem = nullif(btrim(p->>'quem'), ''), status = coalesce(nullif(p->>'status', ''), status),
           prioridade = nullif(p->>'prioridade', ''), data = nullif(p->>'data', '')::date, demanda_id = v_dem,
           link = nullif(btrim(p->>'link'), ''), atualizado_em = now(), atualizado_por = left(p_quem, 80)
     WHERE id = v_id AND excluido_em IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'item % não existe', v_id; END IF;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END
$function$;
