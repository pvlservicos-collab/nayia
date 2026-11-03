CREATE OR REPLACE FUNCTION public.crm_zap_conversa(p_chave text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id,
           'quando', coalesce(x.criado_em, x.recebido_em),
           'recebidoEm', x.recebido_em,
           'texto', x.mensagem,
           'tipo', zap_portal(x.origem),
           'autenticado', x.autenticado,
           'anuncio', jsonb_build_object('titulo', NULL, 'url', NULL, 'preco', NULL, 'negocio', zap_negocio(x.transacao),
                                         'codigo', x.codigo))
         ORDER BY coalesce(x.criado_em, x.recebido_em)), '[]'::jsonb)
    FROM privado.zap_lead x WHERE zap_chave(x) = p_chave
$function$;
