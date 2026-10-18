CREATE OR REPLACE FUNCTION public.site_blog_salvar(p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id bigint := nullif(p->>'id', '')::bigint;
  v_slug text := coalesce(blog_slug(p->>'slug'), blog_slug(p->>'titulo'));
  v_base text; v_n int := 1;
  v_codigo integer := nullif(regexp_replace(coalesce(p->>'codigo', ''), '\D', '', 'g'), '')::integer;
  v_faq jsonb := CASE WHEN jsonb_typeof(p->'faq') = 'array' THEN p->'faq' ELSE '[]'::jsonb END;
  v_rel integer[] := CASE WHEN jsonb_typeof(p->'imoveis_relacionados') = 'array'
                          THEN ARRAY(SELECT (x)::int FROM jsonb_array_elements_text(p->'imoveis_relacionados') x WHERE x ~ '^\d+$')
                          ELSE '{}' END;
  v_pub boolean := coalesce((p->>'publicado')::boolean, false);
  v_antes blog_artigo;
BEGIN
  IF nullif(btrim(coalesce(p->>'titulo', '')), '') IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'o artigo precisa de título'); END IF;
  IF v_slug IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'não consegui montar o endereço (slug) a partir do título'); END IF;
  IF coalesce(p->>'categoria', '') NOT IN ('sobre-nos', 'clientes', 'corretores', 'locacao', 'venda') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'escolha a categoria');
  END IF;
  IF v_codigo IS NOT NULL AND NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = v_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o imóvel ' || v_codigo || ' não existe no cadastro');
  END IF;
  IF coalesce(p->>'tipo', 'post') = 'imovel' AND v_codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'post de imóvel precisa do código do imóvel');
  END IF;
  -- slug único
  v_base := left(v_slug, 80);
  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM blog_artigo WHERE slug = v_slug AND id IS DISTINCT FROM v_id) LOOP
    v_n := v_n + 1; v_slug := v_base || '-' || v_n;
  END LOOP;
  IF v_id IS NOT NULL THEN SELECT * INTO v_antes FROM blog_artigo WHERE id = v_id; END IF;

  INSERT INTO blog_artigo AS a (id, slug, titulo, resumo, categoria, tipo, codigo, bairro, corpo, capa_url, capa_alt, autor,
                                palavra_chave, faq, imoveis_relacionados, publicado, publicado_em, seo_nota, criado_por)
  VALUES (coalesce(v_id, nextval('blog_artigo_id_seq')), v_slug, btrim(p->>'titulo'), nullif(btrim(coalesce(p->>'resumo', '')), ''),
          p->>'categoria', coalesce(nullif(p->>'tipo', ''), 'post'), v_codigo, nullif(btrim(coalesce(p->>'bairro', '')), ''),
          coalesce(p->>'corpo', ''), nullif(btrim(coalesce(p->>'capa_url', '')), ''), nullif(btrim(coalesce(p->>'capa_alt', '')), ''),
          coalesce(nullif(btrim(coalesce(p->>'autor', '')), ''), 'Equipe Imob Easy'), nullif(btrim(coalesce(p->>'palavra_chave', '')), ''),
          v_faq, v_rel, v_pub,
          CASE WHEN v_pub THEN coalesce(v_antes.publicado_em, nullif(p->>'publicado_em', '')::timestamptz, now()) ELSE v_antes.publicado_em END,
          nullif(p->>'seo_nota', '')::integer, left(coalesce(p_quem, ''), 80))
  ON CONFLICT (id) DO UPDATE SET
    slug = EXCLUDED.slug, titulo = EXCLUDED.titulo, resumo = EXCLUDED.resumo, categoria = EXCLUDED.categoria, tipo = EXCLUDED.tipo,
    codigo = EXCLUDED.codigo, bairro = EXCLUDED.bairro, corpo = EXCLUDED.corpo, capa_url = EXCLUDED.capa_url, capa_alt = EXCLUDED.capa_alt,
    autor = EXCLUDED.autor, palavra_chave = EXCLUDED.palavra_chave, faq = EXCLUDED.faq, imoveis_relacionados = EXCLUDED.imoveis_relacionados,
    publicado = EXCLUDED.publicado, publicado_em = EXCLUDED.publicado_em, seo_nota = EXCLUDED.seo_nota, atualizado_em = now()
  RETURNING a.id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug);
END
$function$;
