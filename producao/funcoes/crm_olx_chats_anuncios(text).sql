CREATE OR REPLACE FUNCTION public.crm_olx_chats_anuncios(p_conta text)
 RETURNS TABLE(list_id text, codigo integer, negocio text, titulo text, preco numeric, foto text, url text, no_ar boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT ON (h.list_id)
         h.list_id, a.codigo, a.negocio, nullif(a.conteudo->>'subject', ''),
         CASE WHEN a.conteudo->>'price' ~ '^[0-9]+(\.[0-9]+)?$' THEN (a.conteudo->>'price')::numeric END,
         nullif(a.conteudo->'images'->>0, ''), a.url,
         a.estado = 'publicado' AND coalesce(a.olx_status, '') NOT IN ('deleted', 'expired', 'refused')
    FROM privado.olx_chat h
    JOIN privado.olx_anuncio a ON a.list_id = h.list_id
   WHERE h.conta = p_conta AND h.list_id IS NOT NULL
   ORDER BY h.list_id, a.enviado_em DESC NULLS LAST, a.id DESC
$function$;
