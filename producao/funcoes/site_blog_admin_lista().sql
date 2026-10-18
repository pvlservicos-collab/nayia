CREATE OR REPLACE FUNCTION public.site_blog_admin_lista()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'slug', a.slug, 'titulo', a.titulo, 'resumo', a.resumo, 'categoria', a.categoria,
           'categoria_nome', blog_categoria_nome(a.categoria), 'tipo', a.tipo, 'codigo', a.codigo, 'capa_url', a.capa_url,
           'publicado', a.publicado, 'publicado_em', a.publicado_em, 'atualizado_em', a.atualizado_em, 'seo_nota', a.seo_nota,
           'palavras', coalesce(array_length(regexp_split_to_array(nullif(a.corpo, ''), '\s+'), 1), 0),
           'visitas_7d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 6 AND v.origem NOT LIKE 'rastreador:%'),
           'visitas_30d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 29 AND v.origem NOT LIKE 'rastreador:%'),
           'visitas_total', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.origem NOT LIKE 'rastreador:%'),
           'rastreadores_30d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 29 AND v.origem LIKE 'rastreador:%'))
         ORDER BY a.publicado DESC, coalesce(a.publicado_em, a.atualizado_em) DESC), '[]'::jsonb)
    FROM blog_artigo a
$function$;
