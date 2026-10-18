-- 408: SCRAP — PASTAS E BLACKLIST
--
-- Pedro, 18/10/2026: "pegar as listas novas da OLX e separar elas em uma pasta lá em scrap, depois pegar todas as outras
-- listas de contatos que eu tinha de proprietários e corretores, e verificar todos os contatos que falamos nos últimos 60
-- dias e pôr eles na blacklist, ou seja, não vão fazer parte dessas novas listas ... temos 4, serão 8, porque uma vai ter
-- as imobiliárias e outra só corretores direto, e vai tirar duplicados, tirar gente que já falamos em 60 dias".
--
-- O que muda:
--   scrap_lista.pasta      a pasta da lista na lateral (OLX, Base, Blacklist...)
--   scrap_lista.tipo       'lista' (normal) ou 'blacklist': telefone que está numa blacklist NÃO entra em lista normal
--   scrap_lista.bloqueados quantos contatos a blacklist tirou desta lista na última carga
--   scrap_bloqueado(tel)   está em alguma blacklist? (compara pela chave de telefone da casa, nay_fone_chave)
--   scrap_blacklist_60d(l) enche a lista l com quem falou conosco nos últimos 60 dias (privado.falou_conosco: Parceria,
--                          Captação, Nay, CRM, saídas nossas — a mesma memória que o disparo da captação usa)
--   scrap_contatos_rebuild e site_scrap_importar_contatos passam a pular a blacklist (e tiram quem já estava)
--   site_scrap_listas devolve pasta/tipo/bloqueados; site_scrap_lista_salvar aceita pasta e tipo;
--   site_scrap_contatos(NULL) ("Todas") não mistura as blacklists.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE scrap_lista ADD COLUMN IF NOT EXISTS pasta text NOT NULL DEFAULT '';
ALTER TABLE scrap_lista ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'lista';
ALTER TABLE scrap_lista DROP CONSTRAINT IF EXISTS scrap_lista_tipo_check;
ALTER TABLE scrap_lista ADD CONSTRAINT scrap_lista_tipo_check CHECK (tipo IN ('lista', 'blacklist'));
ALTER TABLE scrap_lista ADD COLUMN IF NOT EXISTS bloqueados integer NOT NULL DEFAULT 0;
ALTER TABLE scrap_contato DROP CONSTRAINT IF EXISTS scrap_contato_origem_check;
ALTER TABLE scrap_contato ADD CONSTRAINT scrap_contato_origem_check CHECK (origem IN ('olx', 'manual', 'csv', 'sistema'));
ALTER TABLE scrap_lista DROP CONSTRAINT IF EXISTS scrap_lista_origem_check;
ALTER TABLE scrap_lista ADD CONSTRAINT scrap_lista_origem_check CHECK (origem IN ('olx', 'manual', 'csv', 'sistema'));

-- a chave de telefone da casa (55 + DDD + 8 últimos dígitos): com ou sem o 9, é a mesma pessoa
CREATE OR REPLACE FUNCTION scrap_chave(p text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $function$
  SELECT nay_fone_chave(nay_fone_com_ddi(p))
$function$;
CREATE INDEX IF NOT EXISTS scrap_contato_chave_idx ON scrap_contato (scrap_chave(telefone));

CREATE OR REPLACE FUNCTION scrap_bloqueado(p_telefone text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  SELECT EXISTS (SELECT 1 FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
                  WHERE l.tipo = 'blacklist' AND scrap_chave(c.telefone) = scrap_chave(p_telefone))
$function$;

-- a blacklist de 60 dias: quem falou conosco por qualquer número (privado.falou_conosco, refeita pelo cron da captação).
-- Refaz só as linhas de origem 'sistema'; o que o Pedro pôs à mão na blacklist fica.
CREATE OR REPLACE FUNCTION scrap_blacklist_60d(p_lista bigint, p_dias integer DEFAULT 60)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int; v_tirados int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = p_lista AND tipo = 'blacklist') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'a lista não é uma blacklist');
  END IF;
  DELETE FROM scrap_contato WHERE lista_id = p_lista AND origem = 'sistema';
  -- a chave guarda 55 + DDD + 8 dígitos; celular (8 dígitos começando em 6-9) ganha o 9 de volta
  INSERT INTO scrap_contato (lista_id, telefone, nome, origem, observacao, dados)
  SELECT p_lista,
         CASE WHEN substr(f.chave, 5, 1) IN ('6', '7', '8', '9') THEN substr(f.chave, 3, 2) || '9' || substr(f.chave, 5)
              ELSE substr(f.chave, 3) END,
         coalesce((SELECT c.nome FROM corretores c WHERE scrap_chave(c.telefone) = f.chave AND coalesce(c.nome, '') <> '' LIMIT 1),
                  (SELECT p.nome FROM proprietarios p WHERE scrap_chave(p.telefone) = f.chave AND coalesce(p.nome, '') <> '' LIMIT 1),
                  (SELECT coalesce(nullif(k.nome_completo, ''), nullif(k.nome_whatsapp, '')) FROM nai_contato k
                    WHERE scrap_chave(k.telefone) = f.chave AND coalesce(nullif(k.nome_completo, ''), k.nome_whatsapp, '') <> '' LIMIT 1)),
         'sistema',
         'falou conosco em ' || to_char(f.ultima_em, 'DD/MM/YYYY') || ' (' || array_to_string(f.origens, ', ') || ')',
         jsonb_build_object('ultima_em', f.ultima_em, 'origens', to_jsonb(f.origens))
    FROM privado.falou_conosco f
   WHERE f.ultima_em > now() - make_interval(days => p_dias) AND f.chave ~ '^55\d{10}$'
  ON CONFLICT (lista_id, telefone) DO UPDATE SET observacao = EXCLUDED.observacao, dados = EXCLUDED.dados, atualizado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE scrap_lista SET atualizado_em = now(), descricao = 'Quem falou conosco nos últimos ' || p_dias || ' dias por qualquer número (Parceria, Captação, Nay, CRM e o que nós mandamos). Refeita em ' || to_char(now(), 'DD/MM HH24:MI') || '.'
   WHERE id = p_lista;
  -- quem está na blacklist sai das listas normais vindas de raspagem/CSV (o que foi posto à mão fica)
  WITH t AS (
    DELETE FROM scrap_contato c USING scrap_lista l
     WHERE l.id = c.lista_id AND l.tipo = 'lista' AND c.origem IN ('olx', 'csv') AND scrap_bloqueado(c.telefone)
    RETURNING c.lista_id
  ), n AS (SELECT lista_id, count(*) k FROM t GROUP BY lista_id)
  UPDATE scrap_lista l SET bloqueados = l.bloqueados + n.k FROM n WHERE n.lista_id = l.id;
  SELECT coalesce(sum(bloqueados), 0) INTO v_tirados FROM scrap_lista WHERE tipo = 'lista';
  RETURN jsonb_build_object('ok', true, 'na_blacklist', v_n, 'bloqueados_total', v_tirados);
END
$function$;

-- rebuild: igual à 407, mas pula a blacklist e tira quem já estava
CREATE OR REPLACE FUNCTION scrap_contatos_rebuild(p_lista bigint)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n integer; v_b integer;
BEGIN
  UPDATE scrap_anuncio SET telefones = scrap_telefones_do_texto(descricao)
   WHERE lista_id = p_lista AND descricao IS NOT NULL;

  WITH tel AS (
    SELECT unnest(a.telefones) AS telefone, a.*
      FROM scrap_anuncio a WHERE a.lista_id = p_lista
  ), agr AS (
    SELECT lista_id, telefone,
           mode() WITHIN GROUP (ORDER BY nullif(trim(anunciante), '')) AS nome,
           mode() WITHIN GROUP (ORDER BY anunciante_id) AS anunciante_id,
           bool_or(telefone_mascarado IS NOT NULL AND left(telefone, 7) = left(regexp_replace(telefone_mascarado, '\D', '', 'g'), 7)) AS confirmado,
           count(*)::int AS n_anuncios,
           (SELECT array_agg(DISTINCT b ORDER BY b) FROM unnest(array_agg(bairro)) b WHERE b IS NOT NULL) AS bairros,
           min(preco) AS preco_min, max(preco) AS preco_max,
           (array_agg(url ORDER BY coalesce(data_olx, coletado_em) DESC))[1] AS exemplo_url,
           (array_agg(titulo ORDER BY coalesce(data_olx, coletado_em) DESC))[1] AS exemplo_titulo
      FROM tel GROUP BY lista_id, telefone
  )
  INSERT INTO scrap_contato AS c (lista_id, telefone, nome, anunciante_id, confirmado, n_anuncios, bairros, preco_min, preco_max,
                                  exemplo_url, exemplo_titulo, origem)
  SELECT lista_id, telefone, nome, anunciante_id, confirmado, n_anuncios, coalesce(bairros, '{}'), preco_min, preco_max,
         exemplo_url, exemplo_titulo, 'olx'
    FROM agr WHERE NOT scrap_bloqueado(telefone)
  ON CONFLICT (lista_id, telefone) DO UPDATE SET
    nome = CASE WHEN c.origem = 'olx' THEN EXCLUDED.nome ELSE c.nome END,
    anunciante_id = coalesce(EXCLUDED.anunciante_id, c.anunciante_id),
    confirmado = c.confirmado OR EXCLUDED.confirmado,
    n_anuncios = EXCLUDED.n_anuncios, bairros = EXCLUDED.bairros,
    preco_min = EXCLUDED.preco_min, preco_max = EXCLUDED.preco_max,
    exemplo_url = EXCLUDED.exemplo_url, exemplo_titulo = EXCLUDED.exemplo_titulo,
    atualizado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  DELETE FROM scrap_contato c WHERE c.lista_id = p_lista AND c.origem = 'olx' AND scrap_bloqueado(c.telefone);
  GET DIAGNOSTICS v_b = ROW_COUNT;
  UPDATE scrap_lista SET atualizado_em = now(),
         bloqueados = (SELECT count(DISTINCT telefone) FROM (SELECT unnest(telefones) telefone FROM scrap_anuncio WHERE lista_id = p_lista) x WHERE scrap_bloqueado(telefone))
   WHERE id = p_lista;
  RETURN v_n;
END
$function$;

-- a carga da raspagem devolve também quantos a blacklist segurou
CREATE OR REPLACE FUNCTION site_scrap_importar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_lista bigint; v_nome text; v_n int; v_contatos int; v_sem int; v_bloq int;
BEGIN
  v_lista := nullif(p->'lista'->>'id', '')::bigint;
  v_nome := nullif(trim(p->'lista'->>'nome'), '');
  IF v_lista IS NULL AND v_nome IS NOT NULL THEN SELECT id INTO v_lista FROM scrap_lista WHERE nome = v_nome LIMIT 1; END IF;
  IF v_lista IS NULL THEN
    IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de nome'); END IF;
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por, pasta)
    VALUES (v_nome, p->'lista'->>'descricao', 'olx', p->'lista'->>'url_busca', coalesce(nullif(p->'lista'->>'cor', ''), '#6d28d9'),
            coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem, coalesce(p->'lista'->>'pasta', ''))
    RETURNING id INTO v_lista;
  ELSE
    UPDATE scrap_lista SET url_busca = coalesce(nullif(p->'lista'->>'url_busca', ''), url_busca),
           descricao = coalesce(nullif(p->'lista'->>'descricao', ''), descricao),
           pasta = coalesce(nullif(p->'lista'->>'pasta', ''), pasta), cor = coalesce(nullif(p->'lista'->>'cor', ''), cor),
           atualizado_em = now() WHERE id = v_lista;
  END IF;

  INSERT INTO scrap_anuncio AS a (lista_id, olx_id, titulo, preco, preco_texto, preco_antigo, categoria, tipo_negocio, subtipo, quartos, banheiros,
                                  vagas, area_m2, condominio, iptu, bairro, cep, lat, lng, anunciante, anunciante_id, telefone_mascarado,
                                  descricao, fotos, n_fotos, url, data_olx, publicado_em, dados)
  SELECT v_lista, (x->>'olx_id')::bigint, x->>'titulo', (x->>'preco')::numeric, x->>'preco_texto', x->>'preco_antigo', x->>'categoria',
         x->>'tipo_negocio', x->>'subtipo', (x->>'quartos')::int, (x->>'banheiros')::int, (x->>'vagas')::int, (x->>'area_m2')::numeric,
         (x->>'condominio_valor')::numeric, (x->>'iptu_valor')::numeric, x->>'bairro', x->>'cep', (x->>'lat')::double precision,
         (x->>'lng')::double precision, nullif(trim(x->>'anunciante'), ''), x->>'anunciante_id', x->>'telefone_mascarado', x->>'descricao',
         coalesce((SELECT array_agg(f) FROM jsonb_array_elements_text(coalesce(x->'fotos', '[]'::jsonb)) f), '{}'),
         (x->>'n_fotos')::int, x->>'url', (x->>'data')::timestamptz, (x->>'publicado_em')::timestamptz,
         coalesce(x->'dados', '{}'::jsonb)
    FROM jsonb_array_elements(coalesce(p->'anuncios', '[]'::jsonb)) x
   WHERE (x->>'olx_id') IS NOT NULL
  ON CONFLICT (lista_id, olx_id) DO UPDATE SET
    titulo = EXCLUDED.titulo, preco = EXCLUDED.preco, preco_texto = EXCLUDED.preco_texto, preco_antigo = EXCLUDED.preco_antigo,
    categoria = EXCLUDED.categoria, tipo_negocio = EXCLUDED.tipo_negocio, subtipo = EXCLUDED.subtipo, quartos = EXCLUDED.quartos,
    banheiros = EXCLUDED.banheiros, vagas = EXCLUDED.vagas, area_m2 = EXCLUDED.area_m2, condominio = EXCLUDED.condominio, iptu = EXCLUDED.iptu,
    bairro = EXCLUDED.bairro, cep = coalesce(EXCLUDED.cep, a.cep), lat = coalesce(EXCLUDED.lat, a.lat), lng = coalesce(EXCLUDED.lng, a.lng),
    anunciante = coalesce(EXCLUDED.anunciante, a.anunciante), anunciante_id = coalesce(EXCLUDED.anunciante_id, a.anunciante_id),
    telefone_mascarado = coalesce(EXCLUDED.telefone_mascarado, a.telefone_mascarado), descricao = coalesce(EXCLUDED.descricao, a.descricao),
    fotos = CASE WHEN cardinality(EXCLUDED.fotos) > 0 THEN EXCLUDED.fotos ELSE a.fotos END, n_fotos = coalesce(EXCLUDED.n_fotos, a.n_fotos),
    url = coalesce(EXCLUDED.url, a.url), data_olx = coalesce(EXCLUDED.data_olx, a.data_olx), publicado_em = coalesce(EXCLUDED.publicado_em, a.publicado_em),
    dados = a.dados || EXCLUDED.dados, coletado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_contatos := scrap_contatos_rebuild(v_lista);
  SELECT count(*) INTO v_sem FROM scrap_anuncio WHERE lista_id = v_lista AND cardinality(telefones) = 0;
  SELECT bloqueados INTO v_bloq FROM scrap_lista WHERE id = v_lista;
  RETURN jsonb_build_object('ok', true, 'lista_id', v_lista, 'anuncios', v_n, 'contatos', v_contatos, 'anuncios_sem_telefone', v_sem, 'bloqueados', v_bloq);
END
$function$;

-- CSV/mão em lote: pula a blacklist (a não ser que a lista de destino seja uma blacklist ou p_ignorar_blacklist)
DROP FUNCTION IF EXISTS site_scrap_importar_contatos(bigint, jsonb, text);
CREATE OR REPLACE FUNCTION site_scrap_importar_contatos(p_lista bigint, p jsonb, p_quem text DEFAULT NULL, p_ignorar_blacklist boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int; v_invalidos int; v_repetidos int; v_total int; v_bloq int := 0; v_tipo text; v_origem text;
BEGIN
  SELECT tipo INTO v_tipo FROM scrap_lista WHERE id = p_lista;
  IF v_tipo IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  v_origem := coalesce(nullif(p->0->>'_origem', ''), 'csv');
  CREATE TEMP TABLE _entrada ON COMMIT DROP AS
    SELECT scrap_telefone_normalizar(x->>'telefone') AS telefone, nullif(trim(x->>'nome'), '') AS nome, nullif(trim(x->>'empresa'), '') AS empresa,
           nullif(trim(x->>'observacao'), '') AS observacao,
           coalesce((SELECT array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> '') FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(x->'etiquetas') = 'array' THEN x->'etiquetas' ELSE '[]'::jsonb END) e), '{}') AS etiquetas,
           CASE WHEN jsonb_typeof(x->'dados') = 'object' THEN x->'dados' ELSE '{}'::jsonb END AS dados
      FROM jsonb_array_elements(coalesce(p, '[]'::jsonb)) x;
  SELECT count(*) INTO v_total FROM _entrada;
  SELECT count(*) INTO v_invalidos FROM _entrada WHERE telefone IS NULL;
  IF v_tipo = 'lista' AND NOT p_ignorar_blacklist THEN
    DELETE FROM _entrada WHERE telefone IS NOT NULL AND scrap_bloqueado(telefone);
    GET DIAGNOSTICS v_bloq = ROW_COUNT;
  END IF;
  INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, observacao, etiquetas, dados)
  SELECT DISTINCT ON (telefone) p_lista, telefone, nome, empresa, CASE WHEN v_origem IN ('olx', 'manual', 'csv', 'sistema') THEN v_origem ELSE 'csv' END,
         observacao, etiquetas, dados || jsonb_build_object('criado_por', p_quem)
    FROM _entrada WHERE telefone IS NOT NULL ORDER BY telefone, nome NULLS LAST
  ON CONFLICT (lista_id, telefone) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_repetidos := v_total - v_invalidos - v_bloq - v_n;
  DROP TABLE _entrada;
  UPDATE scrap_lista SET atualizado_em = now(), bloqueados = bloqueados + v_bloq WHERE id = p_lista;
  RETURN jsonb_build_object('ok', true, 'inseridos', v_n, 'invalidos', v_invalidos, 'repetidos', v_repetidos, 'bloqueados', v_bloq);
END
$function$;

-- contato à mão numa lista normal: avisa se está na blacklist (não bloqueia: foi o Pedro quem pôs)
CREATE OR REPLACE FUNCTION site_scrap_contato_salvar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_tel text; v_lista bigint := nullif(p->>'lista_id', '')::bigint; v_et text[]; v_aviso text;
BEGIN
  IF p ? 'etiquetas' THEN
    SELECT coalesce(array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> ''), '{}') INTO v_et FROM jsonb_array_elements_text(coalesce(p->'etiquetas', '[]'::jsonb)) e;
  END IF;
  IF v_id IS NULL THEN
    v_tel := scrap_telefone_normalizar(p->>'telefone');
    IF v_tel IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'telefone inválido'); END IF;
    IF v_lista IS NULL OR NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = v_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'escolha a lista'); END IF;
    IF EXISTS (SELECT 1 FROM scrap_contato WHERE lista_id = v_lista AND telefone = v_tel) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'esse telefone já está nesta lista', 'telefone', scrap_telefone_formatar(v_tel));
    END IF;
    IF scrap_bloqueado(v_tel) AND (SELECT tipo FROM scrap_lista WHERE id = v_lista) = 'lista' THEN v_aviso := 'esse número está na blacklist (falamos há pouco); entrou mesmo assim'; END IF;
    INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, status, etiquetas, observacao, dados)
    VALUES (v_lista, v_tel, nullif(trim(p->>'nome'), ''), nullif(trim(p->>'empresa'), ''), 'manual',
            coalesce(nullif(p->>'status', ''), 'novo'), coalesce(v_et, '{}'), nullif(trim(p->>'observacao'), ''),
            jsonb_build_object('criado_por', p_quem))
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id, 'criado', true, 'aviso', v_aviso);
  END IF;
  IF p ? 'telefone' THEN
    v_tel := scrap_telefone_normalizar(p->>'telefone');
    IF v_tel IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'telefone inválido'); END IF;
    IF EXISTS (SELECT 1 FROM scrap_contato c WHERE c.telefone = v_tel AND c.id <> v_id AND c.lista_id = (SELECT lista_id FROM scrap_contato WHERE id = v_id)) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'esse telefone já está nesta lista');
    END IF;
  END IF;
  UPDATE scrap_contato SET
    nome = CASE WHEN p ? 'nome' THEN nullif(trim(p->>'nome'), '') ELSE nome END,
    telefone = coalesce(v_tel, telefone),
    empresa = CASE WHEN p ? 'empresa' THEN nullif(trim(p->>'empresa'), '') ELSE empresa END,
    status = CASE WHEN p ? 'status' THEN coalesce(nullif(p->>'status', ''), status) ELSE status END,
    etiquetas = coalesce(v_et, etiquetas),
    observacao = CASE WHEN p ? 'observacao' THEN nullif(trim(p->>'observacao'), '') ELSE observacao END,
    origem = CASE WHEN p ? 'nome' AND origem IN ('olx', 'sistema') THEN 'manual' ELSE origem END,
    atualizado_em = now()
   WHERE id = v_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'contato não existe'); END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

-- as listas: agora com pasta, tipo e bloqueados; e a lista das pastas
CREATE OR REPLACE FUNCTION site_scrap_listas()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
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

CREATE OR REPLACE FUNCTION site_scrap_lista_salvar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_nome text := nullif(trim(p->>'nome'), ''); v_tipo text := nullif(p->>'tipo', '');
BEGIN
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de um nome'); END IF;
  IF v_tipo IS NOT NULL AND v_tipo NOT IN ('lista', 'blacklist') THEN RETURN jsonb_build_object('ok', false, 'erro', 'tipo inválido'); END IF;
  IF v_id IS NULL THEN
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por, pasta, tipo)
    VALUES (v_nome, nullif(trim(p->>'descricao'), ''), coalesce(nullif(p->>'origem', ''), 'manual'), nullif(trim(p->>'url_busca'), ''),
            coalesce(nullif(p->>'cor', ''), CASE WHEN v_tipo = 'blacklist' THEN '#4b5563' ELSE '#6d28d9' END),
            coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem, coalesce(trim(p->>'pasta'), ''), coalesce(v_tipo, 'lista'))
    RETURNING id INTO v_id;
  ELSE
    UPDATE scrap_lista SET nome = v_nome, descricao = CASE WHEN p ? 'descricao' THEN nullif(trim(p->>'descricao'), '') ELSE descricao END,
           url_busca = CASE WHEN p ? 'url_busca' THEN nullif(trim(p->>'url_busca'), '') ELSE url_busca END, cor = coalesce(nullif(p->>'cor', ''), cor),
           pasta = CASE WHEN p ? 'pasta' THEN coalesce(trim(p->>'pasta'), '') ELSE pasta END, tipo = coalesce(v_tipo, tipo),
           ordem = coalesce((p->>'ordem')::int, ordem), atualizado_em = now()
     WHERE id = v_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

-- "Todas" = só as listas normais
CREATE OR REPLACE FUNCTION site_scrap_contatos(p_lista bigint DEFAULT NULL, p_busca text DEFAULT NULL, p_status text DEFAULT NULL,
                                               p_etiqueta text DEFAULT NULL, p_bairro text DEFAULT NULL,
                                               p_ordem text DEFAULT 'anuncios', p_limite int DEFAULT 200, p_desloc int DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_busca text := nullif(trim(p_busca), ''); v_dig text; v_total int; v_itens jsonb; v_bairros jsonb;
BEGIN
  v_dig := nullif(regexp_replace(coalesce(v_busca, ''), '\D', '', 'g'), '');
  WITH base AS MATERIALIZED (
    SELECT c.*, l.nome AS lista_nome, l.cor AS lista_cor, l.tipo AS lista_tipo,
           (SELECT array_agg(DISTINCT l2.nome ORDER BY l2.nome) FROM scrap_contato c2 JOIN scrap_lista l2 ON l2.id = c2.lista_id
             WHERE c2.telefone = c.telefone AND c2.id <> c.id AND l2.tipo = 'lista') AS tambem_em,
           (p_lista IS NOT NULL AND l.tipo = 'lista' AND scrap_bloqueado(c.telefone)) AS na_blacklist
      FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
     WHERE (CASE WHEN p_lista IS NULL THEN l.tipo = 'lista' ELSE c.lista_id = p_lista END)
       AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
       AND (p_etiqueta IS NULL OR p_etiqueta = '' OR p_etiqueta = ANY (c.etiquetas))
       AND (p_bairro IS NULL OR p_bairro = '' OR p_bairro = ANY (c.bairros))
       AND (v_busca IS NULL
            OR c.nome ILIKE '%' || v_busca || '%' OR c.empresa ILIKE '%' || v_busca || '%' OR c.observacao ILIKE '%' || v_busca || '%'
            OR c.exemplo_titulo ILIKE '%' || v_busca || '%'
            OR (v_dig IS NOT NULL AND c.telefone LIKE '%' || v_dig || '%'))
  ), uma AS (
    SELECT DISTINCT ON (CASE WHEN p_lista IS NULL THEN telefone ELSE id::text END) *
      FROM base ORDER BY (CASE WHEN p_lista IS NULL THEN telefone ELSE id::text END), n_anuncios DESC, id
  ), ord AS (
    SELECT * FROM uma
     ORDER BY CASE WHEN p_ordem = 'nome' THEN lower(coalesce(nome, 'zzz')) END,
              CASE WHEN p_ordem = 'recentes' THEN atualizado_em END DESC,
              CASE WHEN p_ordem = 'anuncios' OR p_ordem IS NULL THEN n_anuncios END DESC,
              id
  )
  SELECT count(*), (SELECT jsonb_agg(to_jsonb(x) - 'dados' || jsonb_build_object('telefone_fmt', scrap_telefone_formatar(x.telefone))) FROM (SELECT * FROM ord LIMIT greatest(p_limite, 1) OFFSET greatest(p_desloc, 0)) x)
    INTO v_total, v_itens FROM ord;
  SELECT coalesce(jsonb_agg(jsonb_build_object('bairro', b, 'n', n) ORDER BY n DESC, b), '[]'::jsonb) INTO v_bairros
    FROM (SELECT unnest(c.bairros) b, count(*) n FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
           WHERE (CASE WHEN p_lista IS NULL THEN l.tipo = 'lista' ELSE c.lista_id = p_lista END) GROUP BY 1 ORDER BY 2 DESC LIMIT 40) y;
  RETURN jsonb_build_object('total', v_total, 'contatos', coalesce(v_itens, '[]'::jsonb), 'bairros', v_bairros);
END
$function$;

REVOKE ALL ON FUNCTION public.scrap_bloqueado(text), public.scrap_blacklist_60d(bigint, integer),
  public.site_scrap_importar_contatos(bigint, jsonb, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scrap_chave(text), public.scrap_bloqueado(text) TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.scrap_blacklist_60d(bigint, integer), public.site_scrap_importar_contatos(bigint, jsonb, text, boolean) TO nay_site_escrita;
COMMIT;
