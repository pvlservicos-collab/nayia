CREATE OR REPLACE FUNCTION public.olx_anuncio_registrar(p_ad_id text, p_acao text, p_detalhe jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_anuncio_log (ad_id, acao, detalhe) VALUES (p_ad_id, p_acao, p_detalhe);
$function$;
