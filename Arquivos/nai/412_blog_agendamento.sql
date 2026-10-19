-- 412: BLOG — artigo agendado (19/10/2026)
--
-- Pedro: "peguei uma lista de post para nosso blog ... programa lá 2 por dia ... e lá no blog põe uma agenda de
-- planejamento com os posts que vão sair". O artigo ganha `agendado_para`: fica rascunho até a hora, e o cron
-- (blog_publicar_agendados, de 5 em 5 min no /etc/cron.d/nay-blog) publica carimbando publicado_em = agendado_para.
-- As funções públicas não mudam: só publicado=true aparece; sitemap, feed e home continuam dinâmicos.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE blog_artigo ADD COLUMN IF NOT EXISTS agendado_para timestamptz;
CREATE INDEX IF NOT EXISTS blog_artigo_agendado ON blog_artigo (agendado_para) WHERE NOT publicado AND agendado_para IS NOT NULL;

-- o cron: o que chegou na hora entra no ar
CREATE OR REPLACE FUNCTION public.blog_publicar_agendados()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int;
BEGIN
  UPDATE blog_artigo SET publicado = true, publicado_em = agendado_para, agendado_para = NULL, atualizado_em = now()
   WHERE NOT publicado AND agendado_para IS NOT NULL AND agendado_para <= now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$function$;

-- a lista do admin mostra o agendamento
CREATE OR REPLACE FUNCTION public.site_blog_admin_lista()
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', a.id, 'slug', a.slug, 'titulo', a.titulo, 'resumo', a.resumo, 'categoria', a.categoria,
           'categoria_nome', blog_categoria_nome(a.categoria), 'tipo', a.tipo, 'codigo', a.codigo, 'capa_url', a.capa_url,
           'publicado', a.publicado, 'publicado_em', a.publicado_em, 'agendado_para', a.agendado_para, 'atualizado_em', a.atualizado_em, 'seo_nota', a.seo_nota,
           'palavra_chave', a.palavra_chave,
           'palavras', coalesce(array_length(regexp_split_to_array(nullif(a.corpo, ''), '\s+'), 1), 0),
           'visitas_7d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 6 AND v.origem NOT LIKE 'rastreador:%'),
           'visitas_30d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 29 AND v.origem NOT LIKE 'rastreador:%'),
           'visitas_total', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.origem NOT LIKE 'rastreador:%'),
           'rastreadores_30d', (SELECT coalesce(sum(n), 0) FROM blog_visita v WHERE v.artigo_id = a.id AND v.dia >= current_date - 29 AND v.origem LIKE 'rastreador:%'))
         ORDER BY a.publicado DESC, coalesce(a.publicado_em, a.agendado_para, a.atualizado_em) DESC), '[]'::jsonb)
    FROM blog_artigo a
$function$;

-- salvar: aceita agendado_para (só vale enquanto não publicado); publicar limpa o agendamento
CREATE OR REPLACE FUNCTION public.site_blog_salvar(p jsonb, p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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
  v_agendado timestamptz := nullif(p->>'agendado_para', '')::timestamptz;
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
  -- agendar para já = publicar agora
  IF NOT v_pub AND v_agendado IS NOT NULL AND v_agendado <= now() THEN v_pub := true; END IF;
  v_base := left(v_slug, 80);
  v_slug := v_base;
  WHILE EXISTS (SELECT 1 FROM blog_artigo WHERE slug = v_slug AND id IS DISTINCT FROM v_id) LOOP
    v_n := v_n + 1; v_slug := v_base || '-' || v_n;
  END LOOP;
  IF v_id IS NOT NULL THEN SELECT * INTO v_antes FROM blog_artigo WHERE id = v_id; END IF;

  INSERT INTO blog_artigo AS a (id, slug, titulo, resumo, categoria, tipo, codigo, bairro, corpo, capa_url, capa_alt, autor,
                                palavra_chave, faq, imoveis_relacionados, publicado, publicado_em, agendado_para, seo_nota, criado_por)
  VALUES (coalesce(v_id, nextval('blog_artigo_id_seq')), v_slug, btrim(p->>'titulo'), nullif(btrim(coalesce(p->>'resumo', '')), ''),
          p->>'categoria', coalesce(nullif(p->>'tipo', ''), 'post'), v_codigo, nullif(btrim(coalesce(p->>'bairro', '')), ''),
          coalesce(p->>'corpo', ''), nullif(btrim(coalesce(p->>'capa_url', '')), ''), nullif(btrim(coalesce(p->>'capa_alt', '')), ''),
          coalesce(nullif(btrim(coalesce(p->>'autor', '')), ''), 'Equipe Imob Easy'), nullif(btrim(coalesce(p->>'palavra_chave', '')), ''),
          v_faq, v_rel, v_pub,
          CASE WHEN v_pub THEN coalesce(v_antes.publicado_em, v_agendado, nullif(p->>'publicado_em', '')::timestamptz, now()) ELSE v_antes.publicado_em END,
          CASE WHEN v_pub THEN NULL WHEN p ? 'agendado_para' THEN v_agendado ELSE v_antes.agendado_para END,
          nullif(p->>'seo_nota', '')::integer, left(coalesce(p_quem, ''), 80))
  ON CONFLICT (id) DO UPDATE SET
    slug = EXCLUDED.slug, titulo = EXCLUDED.titulo, resumo = EXCLUDED.resumo, categoria = EXCLUDED.categoria, tipo = EXCLUDED.tipo,
    codigo = EXCLUDED.codigo, bairro = EXCLUDED.bairro, corpo = EXCLUDED.corpo, capa_url = EXCLUDED.capa_url, capa_alt = EXCLUDED.capa_alt,
    autor = EXCLUDED.autor, palavra_chave = EXCLUDED.palavra_chave, faq = EXCLUDED.faq, imoveis_relacionados = EXCLUDED.imoveis_relacionados,
    publicado = EXCLUDED.publicado, publicado_em = EXCLUDED.publicado_em, agendado_para = EXCLUDED.agendado_para, seo_nota = EXCLUDED.seo_nota, atualizado_em = now()
  RETURNING a.id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug, 'publicado', v_pub, 'agendado_para', (SELECT agendado_para FROM blog_artigo WHERE id = v_id));
END
$function$;

REVOKE ALL ON FUNCTION public.blog_publicar_agendados() FROM PUBLIC;
COMMIT;
