CREATE OR REPLACE FUNCTION public.crm_imovel_vincular_anuncio(p_codigo integer, p_link text, p_portal text DEFAULT NULL::text, p_id_anuncio text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_normal text := crm_anuncio_link_normal(p_link);
  v_id     text := coalesce(nullif(regexp_replace(coalesce(p_id_anuncio, ''), '\D', '', 'g'), ''), crm_anuncio_id_do_link(p_link));
  v_portal text := lower(coalesce(nullif(btrim(p_portal), ''),
                     CASE WHEN crm_anuncio_link_normal(p_link) LIKE '%olx.com.br%' THEN 'olx' ELSE 'outro' END));
  v_outro  int;
  v_novo   bigint;
BEGIN
  IF p_codigo IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'não existe imóvel com o id ' || coalesce(p_codigo::text, '(vazio)'));
  END IF;
  IF v_normal IS NULL OR v_normal !~ '^[a-z0-9.-]+\.[a-z]{2,}/' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o link não parece um endereço de anúncio');
  END IF;
  -- o mesmo anúncio em DOIS imóveis é erro de quem confirmou: não gravo, aviso
  SELECT a.codigo INTO v_outro FROM imovel_anuncio a
   WHERE a.codigo <> p_codigo AND (a.link_normal = v_normal OR (v_id IS NOT NULL AND a.id_anuncio = v_id AND a.portal = v_portal))
   LIMIT 1;
  IF v_outro IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'id_imovel_atual', v_outro::text,
      'erro', 'este anúncio já está registrado no imóvel ' || v_outro || '; não registrei em outro');
  END IF;
  INSERT INTO imovel_anuncio (codigo, portal, id_anuncio, link, link_normal, registrado_por)
  VALUES (p_codigo, left(v_portal, 30), v_id, left(btrim(p_link), 600), v_normal, left(coalesce(nullif(btrim(p_quem), ''), 'grokbot'), 60))
  ON CONFLICT (codigo, link_normal) DO NOTHING
  RETURNING id INTO v_novo;
  RETURN jsonb_build_object('ok', true, 'id_imovel', p_codigo::text, 'link', v_normal, 'id_anuncio', v_id,
    'ja_estava', v_novo IS NULL,
    'mensagem', CASE WHEN v_novo IS NULL THEN 'esse link já estava registrado nesse imóvel'
                     ELSE 'link registrado: a próxima consulta desse anúncio bate por link' END);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'erro', 'falha ao registrar: ' || SQLERRM);
END
$function$;
