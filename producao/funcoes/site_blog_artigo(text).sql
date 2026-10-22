CREATE OR REPLACE FUNCTION public.site_blog_artigo(p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a blog_artigo; v_im jsonb; v_rel jsonb; v_bairro text;
BEGIN
  SELECT * INTO a FROM blog_artigo WHERE slug = p_slug AND publicado;
  IF a.id IS NULL THEN RETURN NULL; END IF;
  v_im := CASE WHEN a.codigo IS NOT NULL THEN site_blog_card_imovel(a.codigo) END;
  v_bairro := coalesce(a.bairro, v_im->>'bairro');
  SELECT coalesce(jsonb_agg(c) FILTER (WHERE c IS NOT NULL), '[]'::jsonb) INTO v_rel
    FROM unnest(a.imoveis_relacionados) WITH ORDINALITY u(cod, n) CROSS JOIN LATERAL site_blog_card_imovel(u.cod) c;
  RETURN jsonb_build_object(
    'id', a.id, 'slug', a.slug, 'titulo', a.titulo, 'resumo', a.resumo, 'categoria', a.categoria,
    'categoria_nome', blog_categoria_nome(a.categoria), 'tipo', a.tipo, 'codigo', a.codigo, 'bairro', v_bairro,
    'corpo', a.corpo, 'capa_url', a.capa_url, 'capa_alt', a.capa_alt, 'capa_credito', a.capa_credito, 'autor', a.autor, 'palavra_chave', a.palavra_chave,
    'faq', a.faq, 'publicado_em', a.publicado_em, 'atualizado_em', a.atualizado_em,
    'leitura_min', greatest(1, round(array_length(regexp_split_to_array(a.corpo, '\s+'), 1) / 200.0)),
    'imovel', v_im,
    'relacionados', v_rel,
    'proximos', site_blog_imoveis_proximos(a.codigo, v_bairro,
                  a.imoveis_relacionados || coalesce(a.codigo, 0), CASE WHEN a.tipo = 'imovel' THEN 6 ELSE 4 END),
    'outros', coalesce((SELECT jsonb_agg(jsonb_build_object('slug', o.slug, 'titulo', o.titulo, 'resumo', o.resumo,
                                                             'categoria', o.categoria, 'categoria_nome', blog_categoria_nome(o.categoria),
                                                             'capa_url', o.capa_url, 'capa_alt', o.capa_alt, 'publicado_em', o.publicado_em))
                          FROM (SELECT * FROM blog_artigo o WHERE o.publicado AND o.id <> a.id
                                 ORDER BY (o.categoria = a.categoria) DESC, o.publicado_em DESC LIMIT 3) o), '[]'::jsonb));
END
$function$;
