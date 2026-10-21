CREATE OR REPLACE FUNCTION public.crm_cnm_conversa(p_chave text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', x.lead_id,
           'quando', coalesce(x.criado_no_portal, x.recebido_em),
           'recebidoEm', x.recebido_em,
           'texto', x.mensagem,
           'tipo', x.tipo,
           'autenticado', x.autenticado,
           'anuncio', jsonb_build_object('titulo', x.anuncio_titulo, 'url', x.anuncio_url, 'preco', x.valor, 'negocio', x.negocio,
                                         'codigo', x.codigo))
         ORDER BY coalesce(x.criado_no_portal, x.recebido_em)), '[]'::jsonb)
    FROM privado.cnm_lead x WHERE cnm_chave(x) = p_chave
$function$;
