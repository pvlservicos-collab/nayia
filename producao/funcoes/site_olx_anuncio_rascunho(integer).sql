CREATE OR REPLACE FUNCTION public.site_olx_anuncio_rascunho(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'codigo', p_codigo,
    'venda', olx_anuncio_montar(p_codigo, 'venda'),
    'locacao', olx_anuncio_montar(p_codigo, 'locacao'),
    'na_olx', coalesce((SELECT jsonb_agg(jsonb_build_object('negocio', a.negocio, 'ad_id', a.ad_id, 'estado', a.estado,
                                       'url', a.url, 'mensagem', a.mensagem, 'enviado_em', a.enviado_em,
                                       'publicado_em', a.publicado_em, 'removido_em', a.removido_em) ORDER BY a.id)
                          FROM privado.olx_anuncio a WHERE a.codigo = p_codigo), '[]'::jsonb),
    'pedidos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', x.id, 'negocio', x.negocio, 'estado', x.estado,
                                        'resultado', x.resultado, 'criado_em', x.criado_em, 'pedido_por', x.pedido_por)
                                        ORDER BY x.id DESC)
                           FROM (SELECT * FROM privado.olx_anuncio_pedido WHERE codigo = p_codigo ORDER BY id DESC LIMIT 5) x),
                        '[]'::jsonb))
$function$;
