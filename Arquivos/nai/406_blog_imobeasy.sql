-- 406: O BLOG DA IMOB EASY (blog.imobeasy.online)
--
-- Pedro, 17/10/2026: "crie para mim o blog em um modelo de blog com a identidade visual da home ... 2 tipos de artigos,
-- posts de blog e posts de imóveis ... no final uma lista de imóveis próximos ... um buscador de imóveis igual o card
-- na home numa sidebar ... filtros por categoria: Sobre nós, Clientes, Corretores, imóveis de locação, imóveis de
-- venda ... uma newsletter de imóveis para corretores: o corretor se cadastra e recebe no número dele sempre que
-- cadastrarmos um imóvel novo ... otimizado para o Google e para o SEO de IA ... uma ferramenta que checa os posts,
-- um criador e editor de post ... e metrifica as visitas".
--
-- O que mora aqui (tudo público pelo papel do site, só função):
--   blog_artigo                 o artigo (markdown no corpo; slug, categoria, tipo post|imovel, capa, FAQ para a IA)
--   blog_visita                 visitas por artigo, dia e origem (google, ia, social, direto, outro e os rastreadores)
--   blog_newsletter_corretor    quem se cadastrou para receber imóvel novo no WhatsApp
--   blog_newsletter_envio       o que cada corretor já recebeu (nunca o mesmo imóvel duas vezes)
--   site_blog_lista / site_blog_artigo / site_blog_imoveis_proximos      a leitura pública
--   site_blog_visita                                                   o contador
--   site_blog_admin_lista / site_blog_admin_artigo / site_blog_salvar / site_blog_apagar / site_blog_metricas  o admin
--   site_blog_newsletter_cadastrar / _sair / _lista                    a newsletter
--   blog_newsletter_disparar                                            o cron: o imóvel novo vai aos cadastrados pelo
--                                                                       caminho do Enviar imóvel (nai_disparo_enfileirar,
--                                                                       Parceria; as paredes de sempre valem)
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS blog_artigo (
  id             bigserial PRIMARY KEY,
  slug           text NOT NULL UNIQUE,
  titulo         text NOT NULL,
  resumo         text,
  categoria      text NOT NULL CHECK (categoria IN ('sobre-nos', 'clientes', 'corretores', 'locacao', 'venda')),
  tipo           text NOT NULL DEFAULT 'post' CHECK (tipo IN ('post', 'imovel')),
  codigo         integer REFERENCES imoveis(codigo),
  bairro         text,
  corpo          text NOT NULL DEFAULT '',
  capa_url       text,
  capa_alt       text,
  autor          text NOT NULL DEFAULT 'Equipe Imob Easy',
  palavra_chave  text,
  faq            jsonb NOT NULL DEFAULT '[]'::jsonb,
  imoveis_relacionados integer[] NOT NULL DEFAULT '{}',
  publicado      boolean NOT NULL DEFAULT false,
  publicado_em   timestamptz,
  seo_nota       integer,
  criado_por     text,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS blog_artigo_publicado ON blog_artigo (publicado, publicado_em DESC);

CREATE TABLE IF NOT EXISTS blog_visita (
  artigo_id bigint NOT NULL REFERENCES blog_artigo(id) ON DELETE CASCADE,
  dia       date NOT NULL,
  origem    text NOT NULL,
  n         integer NOT NULL DEFAULT 0,
  PRIMARY KEY (artigo_id, dia, origem)
);

CREATE TABLE IF NOT EXISTS blog_newsletter_corretor (
  id              bigserial PRIMARY KEY,
  telefone        text NOT NULL UNIQUE,          -- só dígitos, com 55
  nome            text,
  creci           text,
  ativo           boolean NOT NULL DEFAULT true,
  origem          text NOT NULL DEFAULT 'blog',
  criado_em       timestamptz NOT NULL DEFAULT now(),
  saiu_em         timestamptz,
  ultimo_envio_em timestamptz
);

CREATE TABLE IF NOT EXISTS blog_newsletter_envio (
  id          bigserial PRIMARY KEY,
  corretor_id bigint NOT NULL REFERENCES blog_newsletter_corretor(id) ON DELETE CASCADE,
  codigo      integer NOT NULL,
  enviado_em  timestamptz NOT NULL DEFAULT now(),
  resultado   text,
  UNIQUE (corretor_id, codigo)
);

-- o nome de cada categoria, num lugar só
CREATE OR REPLACE FUNCTION public.blog_categoria_nome(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE p WHEN 'sobre-nos' THEN 'Sobre nós' WHEN 'clientes' THEN 'Clientes' WHEN 'corretores' THEN 'Corretores'
                WHEN 'locacao' THEN 'Imóveis de locação' WHEN 'venda' THEN 'Imóveis de venda' ELSE coalesce(p, '') END
$function$;

-- o slug a partir do título: sem acento, minúsculo, hífens
CREATE OR REPLACE FUNCTION public.blog_slug(p text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT nullif(btrim(regexp_replace(regexp_replace(lower(unaccent(coalesce(p, ''))), '[^a-z0-9]+', '-', 'g'), '-{2,}', '-', 'g'), '-'), '')
$function$;

-- o card de um imóvel para o blog (só o que está no ar; de parceiro não)
CREATE OR REPLACE FUNCTION public.site_blog_card_imovel(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
           'codigo', b.codigo, 'tipo', coalesce(b.tipo_original, b.tipo), 'condominio', b.condominio_nome, 'bairro', b.bairro,
           'quartos', b.quartos, 'suites', b.suites, 'vagas', b.vagas, 'area_util', b.area_util,
           'valor_venda', nullif(b.valor_venda, 0), 'valor_aluguel', nullif(b.valor_aluguel, 0),
           'capa', (SELECT f.url FROM imovel_fotos f WHERE f.codigo = b.codigo
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1),
           'url', 'https://imobeasy.online/imovel/' || b.codigo)
    FROM core_imovel_busca b
   WHERE b.codigo = p_codigo AND b.ofertavel AND NOT coalesce(b.e_parceiro, false)
$function$;

-- os imóveis perto: do mesmo lugar do imóvel do post (pelo mapa), ou do bairro do post, ou os mais novos
CREATE OR REPLACE FUNCTION public.site_blog_imoveis_proximos(p_codigo integer, p_bairro text, p_excluir integer[] DEFAULT '{}',
                                                             p_limite integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_lat double precision; v_lon double precision; v_loc boolean; v_norm text; v jsonb;
BEGIN
  SELECT g.lat, g.lon INTO v_lat, v_lon FROM imovel_geo g WHERE g.codigo = p_codigo;
  SELECT b.de_locacao INTO v_loc FROM core_imovel_busca b WHERE b.codigo = p_codigo;
  v_norm := nay_normalizar_lugar(p_bairro, true);
  SELECT coalesce(jsonb_agg(c.card ORDER BY c.ordem), '[]'::jsonb) INTO v
    FROM (SELECT site_blog_card_imovel(b.codigo) AS card,
                 CASE WHEN v_lat IS NOT NULL AND g.lat IS NOT NULL
                      THEN sqrt(power((g.lat - v_lat) * 111.0, 2) + power((g.lon - v_lon) * 107.0, 2))
                      WHEN v_norm IS NOT NULL AND b.bairro_norm = v_norm THEN 50
                      ELSE 500 END
                 + CASE WHEN v_loc IS NOT NULL AND b.de_locacao = v_loc THEN 0 ELSE 20 END
                 - least(coalesce(b.qtd_fotos, 0), 10) * 0.01 AS ordem
            FROM core_imovel_busca b
            LEFT JOIN imovel_geo g ON g.codigo = b.codigo
           WHERE b.ofertavel AND NOT coalesce(b.e_parceiro, false) AND coalesce(b.qtd_fotos, 0) > 0
             AND b.codigo <> coalesce(p_codigo, 0) AND NOT (b.codigo = ANY (coalesce(p_excluir, '{}')))
           ORDER BY ordem, b.codigo DESC
           LIMIT greatest(1, least(coalesce(p_limite, 4), 12))) c
   WHERE c.card IS NOT NULL;
  RETURN v;
END
$function$;

-- a lista pública (só publicados)
CREATE OR REPLACE FUNCTION public.site_blog_lista(p_categoria text DEFAULT NULL, p_busca text DEFAULT NULL,
                                                  p_limite integer DEFAULT 12, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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

-- um artigo público, com o imóvel dele, os relacionados, os próximos e outros artigos
CREATE OR REPLACE FUNCTION public.site_blog_artigo(p_slug text)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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
    'corpo', a.corpo, 'capa_url', a.capa_url, 'capa_alt', a.capa_alt, 'autor', a.autor, 'palavra_chave', a.palavra_chave,
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

-- o contador: por artigo, dia (Manaus) e origem
CREATE OR REPLACE FUNCTION public.site_blog_visita(p_slug text, p_origem text)
 RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint;
BEGIN
  SELECT id INTO v_id FROM blog_artigo WHERE slug = p_slug AND publicado;
  IF v_id IS NULL THEN RETURN false; END IF;
  INSERT INTO blog_visita (artigo_id, dia, origem, n)
  VALUES (v_id, (now() AT TIME ZONE 'America/Manaus')::date, left(coalesce(nullif(btrim(p_origem), ''), 'direto'), 40), 1)
  ON CONFLICT (artigo_id, dia, origem) DO UPDATE SET n = blog_visita.n + 1;
  RETURN true;
END
$function$;

-- ADMIN: a lista com as visitas
CREATE OR REPLACE FUNCTION public.site_blog_admin_lista()
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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

CREATE OR REPLACE FUNCTION public.site_blog_admin_artigo(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT to_jsonb(a) || jsonb_build_object('categoria_nome', blog_categoria_nome(a.categoria),
           'imovel', CASE WHEN a.codigo IS NOT NULL THEN site_blog_card_imovel(a.codigo) END)
    FROM blog_artigo a WHERE a.id = p_id
$function$;

-- ADMIN: criar ou salvar (o slug nasce do título e nunca repete; publicar carimba a primeira data)
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

CREATE OR REPLACE FUNCTION public.site_blog_apagar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  DELETE FROM blog_artigo WHERE id = p_id;
  RETURN jsonb_build_object('ok', FOUND);
END
$function$;

-- ADMIN: as visitas por dia e origem, e por artigo
CREATE OR REPLACE FUNCTION public.site_blog_metricas(p_de date DEFAULT NULL, p_ate date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH lim AS (SELECT coalesce(p_de, current_date - 29) AS de, coalesce(p_ate, current_date) AS ate),
  v AS (SELECT * FROM blog_visita, lim WHERE dia BETWEEN lim.de AND lim.ate)
  SELECT jsonb_build_object(
    'de', (SELECT de FROM lim), 'ate', (SELECT ate FROM lim),
    'dias', (SELECT jsonb_agg(d ORDER BY d) FROM generate_series((SELECT de FROM lim), (SELECT ate FROM lim), '1 day') d),
    'por_origem', (SELECT coalesce(jsonb_object_agg(o, s), '{}'::jsonb) FROM (
        SELECT o, jsonb_agg(coalesce(x.n, 0) ORDER BY d) AS s
          FROM unnest(ARRAY['google', 'ia', 'social', 'direto', 'outro', 'rastreador']) o
         CROSS JOIN generate_series((SELECT de FROM lim), (SELECT ate FROM lim), '1 day') d
          LEFT JOIN LATERAL (SELECT sum(n) AS n FROM v WHERE v.dia = d
                              AND CASE WHEN o = 'rastreador' THEN v.origem LIKE 'rastreador:%' ELSE v.origem = o END) x ON true
         GROUP BY o) q),
    'rastreadores', (SELECT coalesce(jsonb_object_agg(origem, n), '{}'::jsonb) FROM
        (SELECT replace(origem, 'rastreador:', '') AS origem, sum(n) AS n FROM v WHERE origem LIKE 'rastreador:%' GROUP BY 1) r),
    'total', (SELECT coalesce(sum(n), 0) FROM v WHERE origem NOT LIKE 'rastreador:%'),
    'artigos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'slug', a.slug, 'titulo', a.titulo, 'categoria', a.categoria,
                   'visitas', x.humanas, 'google', x.google, 'ia', x.ia, 'rastreadores', x.rastr) ORDER BY x.humanas DESC, x.rastr DESC), '[]'::jsonb)
      FROM blog_artigo a
      JOIN LATERAL (SELECT coalesce(sum(n) FILTER (WHERE origem NOT LIKE 'rastreador:%'), 0) AS humanas,
                           coalesce(sum(n) FILTER (WHERE origem = 'google'), 0) AS google,
                           coalesce(sum(n) FILTER (WHERE origem = 'ia'), 0) AS ia,
                           coalesce(sum(n) FILTER (WHERE origem LIKE 'rastreador:%'), 0) AS rastr
                      FROM v WHERE v.artigo_id = a.id) x ON true
     WHERE x.humanas > 0 OR x.rastr > 0))
$function$;

-- NEWSLETTER: cadastrar (volta quem saiu), sair e a lista
CREATE OR REPLACE FUNCTION public.site_blog_newsletter_cadastrar(p_nome text, p_telefone text, p_creci text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'); v_id bigint; v_novo boolean; v_nome text; v_turno bigint;
BEGIN
  IF v_tel ~ '^55' AND length(v_tel) IN (12, 13) THEN NULL;
  ELSIF length(v_tel) IN (10, 11) THEN v_tel := '55' || v_tel;
  ELSE RETURN jsonb_build_object('ok', false, 'erro', 'Confira o WhatsApp: use DDD + número, ex.: 92 99999-9999.');
  END IF;
  v_nome := nullif(left(btrim(coalesce(p_nome, '')), 80), '');
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Diga o seu nome.'); END IF;
  INSERT INTO blog_newsletter_corretor AS c (telefone, nome, creci, ativo, criado_em, saiu_em)
  VALUES (v_tel, v_nome, nullif(left(btrim(coalesce(p_creci, '')), 30), ''), true, now(), NULL)
  ON CONFLICT (telefone) DO UPDATE SET nome = EXCLUDED.nome, creci = coalesce(EXCLUDED.creci, c.creci), ativo = true, saiu_em = NULL,
                                       criado_em = CASE WHEN c.ativo THEN c.criado_em ELSE now() END
  RETURNING id, (xmax = 0) INTO v_id, v_novo;
  -- as boas-vindas saem pelo caminho do Enviar imóvel (papel 'entrega', pela Parceria): a parede exige um turno de
  -- comando do Tel, como o nai_disparo_enfileirar faz
  IF v_novo THEN
    INSERT INTO nai_turno (contato_id, papel, texto)
    VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel', left('newsletter do blog: boas-vindas para ' || v_tel, 500))
    RETURNING id INTO v_turno;
    PERFORM nai_enfileirar_texto(v_turno, NULL, nai_contato_do_cadastro(v_tel, v_nome), 'entrega',
      'Olá, ' || split_part(v_nome, ' ', 1) || '! Aqui é a Nay, da Imob Easy. Você entrou na nossa lista de imóveis novos: '
      || 'sempre que cadastrarmos um imóvel, te mando o card por aqui. Parceria de 50% em todos. '
      || 'Para sair da lista é só responder SAIR DA LISTA.', 'newsletter_boas_vindas', 0, now() + interval '2 seconds');
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'novo', v_novo);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_blog_newsletter_sair(p_telefone text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
BEGIN
  IF length(v_tel) IN (10, 11) THEN v_tel := '55' || v_tel; END IF;
  UPDATE blog_newsletter_corretor SET ativo = false, saiu_em = now() WHERE telefone = v_tel AND ativo;
  RETURN jsonb_build_object('ok', FOUND);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_blog_newsletter_lista()
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
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

-- O CRON: o imóvel novo (cadastrado depois do cadastro do corretor, no ar, com foto, não de parceiro) vai a cada
-- cadastrado, pelo Enviar imóvel (Parceria). Até 3 por rodada e 10 por dia para cada um; nunca o mesmo duas vezes.
CREATE OR REPLACE FUNCTION public.blog_newsletter_disparar()
 RETURNS integer
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE c record; v_cods integer[]; v_res text; v_n integer := 0; v_hora int := extract(hour FROM now() AT TIME ZONE 'America/Manaus');
BEGIN
  IF v_hora < 8 OR v_hora >= 20 THEN RETURN 0; END IF;
  FOR c IN SELECT * FROM blog_newsletter_corretor WHERE ativo ORDER BY id LOOP
    CONTINUE WHEN (SELECT count(*) FROM blog_newsletter_envio e WHERE e.corretor_id = c.id AND e.enviado_em > now() - interval '24 hours') >= 10;
    SELECT array_agg(i.codigo ORDER BY i.criado_em) INTO v_cods
      FROM (SELECT i.codigo, i.criado_em
              FROM imoveis i JOIN core_imovel_busca b ON b.codigo = i.codigo
             WHERE i.criado_em > greatest(c.criado_em, now() - interval '7 days')
               AND b.ofertavel AND NOT coalesce(b.e_parceiro, false) AND coalesce(b.qtd_fotos, 0) > 0
               AND NOT EXISTS (SELECT 1 FROM blog_newsletter_envio e WHERE e.corretor_id = c.id AND e.codigo = i.codigo)
             ORDER BY i.criado_em LIMIT 3) i;
    CONTINUE WHEN v_cods IS NULL;
    BEGIN
      v_res := nai_disparo_enfileirar(c.telefone, v_cods, 'newsletter do blog');
    EXCEPTION WHEN OTHERS THEN
      v_res := 'erro: ' || SQLERRM;
    END;
    INSERT INTO blog_newsletter_envio (corretor_id, codigo, resultado)
    SELECT c.id, x, left(v_res, 300) FROM unnest(v_cods) x ON CONFLICT DO NOTHING;
    UPDATE blog_newsletter_corretor SET ultimo_envio_em = now() WHERE id = c.id;
    v_n := v_n + cardinality(v_cods);
  END LOOP;
  RETURN v_n;
END
$function$;

REVOKE ALL ON FUNCTION public.site_blog_card_imovel(integer), public.site_blog_imoveis_proximos(integer, text, integer[], integer),
  public.site_blog_lista(text, text, integer, integer), public.site_blog_artigo(text), public.site_blog_visita(text, text),
  public.site_blog_admin_lista(), public.site_blog_admin_artigo(bigint), public.site_blog_salvar(jsonb, text), public.site_blog_apagar(bigint),
  public.site_blog_metricas(date, date), public.site_blog_newsletter_cadastrar(text, text, text), public.site_blog_newsletter_sair(text),
  public.site_blog_newsletter_lista(), public.blog_newsletter_disparar() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_blog_card_imovel(integer), public.site_blog_imoveis_proximos(integer, text, integer[], integer),
  public.site_blog_lista(text, text, integer, integer), public.site_blog_artigo(text) TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_blog_visita(text, text), public.site_blog_admin_lista(), public.site_blog_admin_artigo(bigint),
  public.site_blog_salvar(jsonb, text), public.site_blog_apagar(bigint), public.site_blog_metricas(date, date),
  public.site_blog_newsletter_cadastrar(text, text, text), public.site_blog_newsletter_sair(text), public.site_blog_newsletter_lista()
  TO nay_site_escrita;
COMMIT;
