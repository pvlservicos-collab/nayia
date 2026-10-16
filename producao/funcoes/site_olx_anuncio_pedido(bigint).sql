CREATE OR REPLACE FUNCTION public.site_olx_anuncio_pedido(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('id', p.id, 'codigo', p.codigo, 'negocio', p.negocio, 'estado', p.estado,
                            'resultado', p.resultado, 'ad_id', p.ad_id, 'criado_em', p.criado_em, 'feito_em', p.feito_em,
                            'na_olx', (SELECT jsonb_build_object('estado', a.estado, 'url', a.url, 'mensagem', a.mensagem)
                                         FROM privado.olx_anuncio a WHERE a.ad_id = p.ad_id ORDER BY a.id DESC LIMIT 1))
    FROM privado.olx_anuncio_pedido p WHERE p.id = p_id
$function$;
