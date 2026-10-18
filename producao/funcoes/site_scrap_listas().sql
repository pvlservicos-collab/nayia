CREATE OR REPLACE FUNCTION public.site_scrap_listas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'listas', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'nome', l.nome, 'descricao', l.descricao, 'origem', l.origem, 'url_busca', l.url_busca, 'cor', l.cor,
        'pasta', l.pasta, 'tipo', l.tipo, 'bloqueados', l.bloqueados,
        'ordem', l.ordem, 'criado_em', l.criado_em, 'atualizado_em', l.atualizado_em,
        'contatos', (SELECT count(*) FROM scrap_contato c WHERE c.lista_id = l.id),
        'por_status', (SELECT coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb) FROM (SELECT status, count(*) n FROM scrap_contato WHERE lista_id = l.id GROUP BY status) s),
        'anuncios', (SELECT count(*) FROM scrap_anuncio a WHERE a.lista_id = l.id),
        'anuncios_sem_telefone', (SELECT count(*) FROM scrap_anuncio a WHERE a.lista_id = l.id AND cardinality(a.telefones) = 0),
        'anunciantes', (SELECT count(DISTINCT coalesce(anunciante_id, anunciante)) FROM scrap_anuncio a WHERE a.lista_id = l.id),
        'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM scrap_contato WHERE lista_id = l.id) x)
      ) ORDER BY l.pasta, l.ordem, l.id) FROM scrap_lista l), '[]'::jsonb),
    'pastas', (SELECT coalesce(jsonb_agg(p ORDER BY p), '[]'::jsonb) FROM (SELECT DISTINCT pasta p FROM scrap_lista WHERE pasta <> '') x),
    'total_contatos', (SELECT count(*) FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id WHERE l.tipo = 'lista'),
    'telefones_distintos', (SELECT count(DISTINCT c.telefone) FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id WHERE l.tipo = 'lista'),
    'na_blacklist', (SELECT count(DISTINCT scrap_chave(c.telefone)) FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id WHERE l.tipo = 'blacklist'),
    'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM scrap_contato) x)
  )
$function$;
