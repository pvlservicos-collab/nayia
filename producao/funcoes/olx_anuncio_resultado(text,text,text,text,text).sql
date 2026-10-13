CREATE OR REPLACE FUNCTION public.olx_anuncio_resultado(p_ad_id text, p_estado text, p_list_id text, p_url text, p_mensagem text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_anuncio
     SET estado = p_estado,
         list_id = coalesce(nullif(btrim(p_list_id), ''), list_id),
         url = coalesce(nullif(btrim(p_url), ''), url),
         mensagem = nullif(left(coalesce(p_mensagem, ''), 500), ''),
         conferido_em = now(), atualizado_em = now(),
         publicado_em = CASE WHEN p_estado = 'publicado' THEN coalesce(publicado_em, now()) ELSE publicado_em END,
         removido_em = CASE WHEN p_estado = 'removido' THEN now() ELSE removido_em END,
         import_token = CASE WHEN p_estado IN ('enviado', 'removendo') THEN import_token END
   WHERE ad_id = p_ad_id;
  PERFORM olx_anuncio_registrar(p_ad_id, 'resultado:' || p_estado, jsonb_build_object('list_id', p_list_id, 'url', p_url, 'mensagem', p_mensagem));
END $function$;
