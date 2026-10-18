CREATE OR REPLACE FUNCTION public.site_blog_newsletter_lista()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'ativos', (SELECT count(*) FROM blog_newsletter_corretor WHERE ativo),
    'total', (SELECT count(*) FROM blog_newsletter_corretor),
    'envios_30d', (SELECT count(*) FROM blog_newsletter_envio WHERE enviado_em > now() - interval '30 days'),
    'corretores', coalesce((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'creci', c.creci,
                      'telefone', regexp_replace(c.telefone, '^55(\d{2})(\d{4,5})(\d{4})$', '\1 \2-\3'),
                      'ativo', c.ativo, 'criado_em', c.criado_em, 'saiu_em', c.saiu_em, 'ultimo_envio_em', c.ultimo_envio_em,
                      'envios', (SELECT count(*) FROM blog_newsletter_envio e WHERE e.corretor_id = c.id),
                      'ja_corretor', nay_e_corretor_chave(nay_fone_chave(c.telefone)))
                    ORDER BY c.ativo DESC, c.criado_em DESC) FROM blog_newsletter_corretor c), '[]'::jsonb))
$function$;
