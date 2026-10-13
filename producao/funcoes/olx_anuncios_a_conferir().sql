CREATE OR REPLACE FUNCTION public.olx_anuncios_a_conferir()
 RETURNS TABLE(ad_id text, conta text, import_token text, estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT a.ad_id, a.conta, a.import_token, a.estado FROM privado.olx_anuncio a
   WHERE a.estado IN ('enviado', 'removendo') AND a.import_token IS NOT NULL ORDER BY a.enviado_em;
$function$;
