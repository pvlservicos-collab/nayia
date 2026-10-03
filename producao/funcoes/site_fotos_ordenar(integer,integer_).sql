CREATE OR REPLACE FUNCTION public.site_fotos_ordenar(p_codigo integer, p_ids integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_todas integer[];
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  SELECT array_agg(id ORDER BY id) INTO v_todas FROM imovel_fotos WHERE codigo = p_codigo AND coalesce(url, '') <> '';
  -- a ordem nova tem de trazer TODAS as fotos do imóvel, cada uma uma vez: a tela pode estar velha
  IF v_todas IS NULL OR p_ids IS NULL OR cardinality(p_ids) <> cardinality(v_todas)
     OR (SELECT array_agg(x ORDER BY x) FROM unnest(p_ids) x) IS DISTINCT FROM v_todas THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'as fotos mudaram enquanto a tela estava aberta: recarregue');
  END IF;
  UPDATE imovel_fotos f SET ordem = x.n, e_capa = (x.n = 1)
    FROM unnest(p_ids) WITH ORDINALITY x(id, n)
   WHERE f.id = x.id AND f.codigo = p_codigo;
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true);
END;
$function$;
