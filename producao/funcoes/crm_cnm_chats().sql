CREATE OR REPLACE FUNCTION public.crm_cnm_chats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH l AS (SELECT x.*, cnm_chave(x) AS chave, coalesce(x.criado_no_portal, x.recebido_em) AS quando FROM privado.cnm_lead x),
       u AS (SELECT DISTINCT ON (chave) * FROM l ORDER BY chave, quando DESC)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'chave', u.chave,
           'nome', (SELECT y.nome FROM l y WHERE y.chave = u.chave AND y.nome IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'telefone', (SELECT y.telefone FROM l y WHERE y.chave = u.chave AND y.telefone IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'email', (SELECT y.email FROM l y WHERE y.chave = u.chave AND y.email IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'leads', (SELECT count(*) FROM l y WHERE y.chave = u.chave),
           'naoLidas', (SELECT count(*) FROM l y WHERE y.chave = u.chave AND y.lido_em IS NULL),
           'criadoEm', (SELECT min(y.quando) FROM l y WHERE y.chave = u.chave),
           'ultimaEm', u.quando,
           'ultimaTexto', coalesce(u.mensagem, u.tipo, 'pediu contato'),
           'tipo', u.tipo,
           'autenticado', u.autenticado,
           'anuncio', jsonb_build_object('titulo', u.anuncio_titulo, 'url', u.anuncio_url, 'preco', u.valor, 'negocio', u.negocio,
                                         'codigo', u.codigo)
                      || coalesce(cnm_anuncio_do_codigo(u.codigo), '{}'::jsonb))
         ORDER BY u.quando DESC), '[]'::jsonb)
    FROM u
$function$;
