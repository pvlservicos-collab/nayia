CREATE OR REPLACE FUNCTION public.olx_nay_contexto(p_chat bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'chat', h.id, 'conta', h.conta, 'chat_id', h.chat_id, 'list_id', h.list_id,
    'cliente', jsonb_build_object('nome', h.nome, 'telefone', h.telefone, 'email', h.email),
    'anuncio', (SELECT jsonb_build_object('ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'url', a.url, 'estado', a.estado,
                                          'titulo', a.conteudo->>'subject', 'preco', a.conteudo->'price')
                  FROM privado.olx_anuncio a WHERE a.list_id = h.list_id ORDER BY a.id DESC LIMIT 1),
    'imovel', (SELECT site_imovel_publico(a.codigo) || jsonb_build_object('link', 'https://imobeasy.online/imovel/' || a.codigo)
                 FROM privado.olx_anuncio a WHERE a.list_id = h.list_id ORDER BY a.id DESC LIMIT 1),
    'com_gente', coalesce((SELECT n.humano_em IS NOT NULL FROM privado.olx_chat_nay n WHERE n.chat = h.id), false),
    'mensagens', coalesce((SELECT jsonb_agg(jsonb_build_object('de', x.de, 'texto', x.texto, 'quando', x.quando, 'por', x.enviada_por) ORDER BY x.id)
                             FROM (SELECT m.* FROM privado.olx_chat_mensagem m WHERE m.chat = h.id ORDER BY m.id DESC LIMIT 60) x), '[]'::jsonb))
    FROM privado.olx_chat h WHERE h.id = p_chat;
$function$;
