CREATE OR REPLACE FUNCTION public.olx_anuncio_na_olx(p_ad_id text, p_list_id text, p_status text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE privado.olx_anuncio
     SET olx_status = p_status, list_id = coalesce(nullif(btrim(p_list_id), ''), list_id), conferido_em = now(), atualizado_em = now(),
         -- a moderação publicou depois da nossa consulta, ou alguém apagou pelo site da OLX
         estado = CASE WHEN p_status = 'published' AND estado = 'enviado' THEN 'publicado'
                       WHEN p_status IN ('deleted', 'deleted_sold') AND estado IN ('publicado', 'enviado', 'removendo') THEN 'removido'
                       ELSE estado END,
         publicado_em = CASE WHEN p_status = 'published' THEN coalesce(publicado_em, now()) ELSE publicado_em END,
         removido_em = CASE WHEN p_status IN ('deleted', 'deleted_sold') THEN coalesce(removido_em, now()) ELSE removido_em END,
         -- estava no ar e sumiu sem a gente pedir: foi apagado pelo site da OLX
         removido_por_fora = removido_por_fora OR (p_status IN ('deleted', 'deleted_sold') AND estado IN ('publicado', 'enviado'))
   WHERE ad_id = p_ad_id AND (olx_status IS DISTINCT FROM p_status OR list_id IS NULL);
$function$;
