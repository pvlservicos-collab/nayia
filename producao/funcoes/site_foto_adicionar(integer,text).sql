CREATE OR REPLACE FUNCTION public.site_foto_adicionar(p_codigo integer, p_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id integer; v_ordem integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'imóvel não encontrado');
  END IF;
  -- só o arquivo que a própria API gravou na pasta deste imóvel
  IF coalesce(p_url, '') !~ ('^https://imobeasy\.online/fotos-captacao/manual/' || p_codigo || '/[A-Za-z0-9_-]+\.(jpg|png|webp)$') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'endereço de foto inválido');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('imovel_fotos'), p_codigo);
  IF EXISTS (SELECT 1 FROM imovel_fotos WHERE codigo = p_codigo AND url = p_url) THEN
    RETURN jsonb_build_object('ok', true, 'ja', true);
  END IF;
  SELECT coalesce(max(ordem), 0) + 1 INTO v_ordem FROM imovel_fotos WHERE codigo = p_codigo;
  INSERT INTO imovel_fotos (codigo, ordem, url, e_capa) VALUES (p_codigo, v_ordem, p_url, false) RETURNING id INTO v_id;
  PERFORM site_fotos_renumerar(p_codigo);
  PERFORM site_fotos_marcar_manual(p_codigo);
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'ordem', (SELECT ordem FROM imovel_fotos WHERE id = v_id));
END;
$function$;
