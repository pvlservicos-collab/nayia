CREATE OR REPLACE FUNCTION public.site_blog_lista(p_categoria text DEFAULT NULL::text, p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 12, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH f AS (
    SELECT a.* FROM blog_artigo a
     WHERE a.publicado
       AND (nullif(p_categoria, '') IS NULL OR a.categoria = p_categoria)
       AND (nullif(btrim(coalesce(p_busca, '')), '') IS NULL
            OR lower(unaccent(a.titulo || ' ' || coalesce(a.resumo, '') || ' ' || a.corpo)) LIKE '%' || lower(unaccent(btrim(p_busca))) || '%')
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM f),
    'categorias', (SELECT jsonb_agg(jsonb_build_object('chave', c.chave, 'nome', blog_categoria_nome(c.chave),
                                                       'total', (SELECT count(*) FROM blog_artigo a WHERE a.publicado AND a.categoria = c.chave)))
                     FROM unnest(ARRAY['sobre-nos', 'clientes', 'corretores', 'locacao', 'venda']) c(chave)),
    'artigos', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'slug', x.slug, 'titulo', x.titulo, 'resumo', x.resumo, 'categoria', x.categoria,
        'categoria_nome', blog_categoria_nome(x.categoria), 'tipo', x.tipo, 'codigo', x.codigo,
        'capa_url', x.capa_url, 'capa_alt', x.capa_alt, 'autor', x.autor,
        'publicado_em', x.publicado_em, 'atualizado_em', x.atualizado_em,
        'leitura_min', greatest(1, round(array_length(regexp_split_to_array(x.corpo, '\s+'), 1) / 200.0)))
        ORDER BY x.publicado_em DESC)
      FROM (SELECT * FROM f ORDER BY publicado_em DESC LIMIT greatest(1, least(coalesce(p_limite, 12), 50)) OFFSET greatest(0, coalesce(p_offset, 0))) x), '[]'::jsonb))
$function$;
