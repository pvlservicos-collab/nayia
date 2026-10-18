-- 407: SCRAP, O GERENCIADOR DE LISTAS (menu Scrap do admin do site)
--
-- Pedro, 18/10/2026: "crie um menu lá no menu que desce do site escrito Scrap e salve essa lista lá das 4 url por
-- coluna, minha ideia é focar nos dados, nome e telefone principalmente, faz uma limpa em duplicados e tire os sem
-- número e monte essas 4 listas lá, essa aba scrap vai ser um grande gerenciador de listas".
--
-- O que mora aqui (tudo pelo papel do site, só função):
--   scrap_lista        a lista (as 4 buscas da OLX de 18/10 e as que ele criar: à mão, por CSV ou por outra raspagem)
--   scrap_anuncio      o anúncio cru que a raspagem trouxe (card da lista + detalhe: descrição, CEP, lat/long, anunciante)
--   scrap_contato      a linha que interessa: NOME + TELEFONE, uma por telefone dentro da lista, com status, etiquetas e
--                      observação; nasce dos anúncios (scrap_contatos_rebuild) ou é digitada/importada
--   scrap_telefone_normalizar / scrap_telefones_do_texto     o telefone limpo (o anunciante escreve "92 9998I-9200")
--   site_scrap_listas / _lista_salvar / _lista_apagar        as listas
--   site_scrap_contatos / _contato_salvar / _contatos_acao   os contatos (buscar, editar, status, etiqueta, mover, apagar)
--   site_scrap_importar / site_scrap_importar_contatos       a carga: anúncios raspados (JSON) e contatos (CSV nome;telefone)
--   site_scrap_anuncios                                       os anúncios de um contato (gaveta de detalhe)
--
-- Por que só telefone da descrição: a OLX só mostra o número inteiro para quem está logado (o "Exibir telefone" chama
-- apigw.olx.com.br/v1/showphone e manda para o login); o que vem aberto é o prefixo mascarado (9299981*...). Quando o
-- prefixo bate com um número achado na descrição, o contato ganha a marca "confirmado pela OLX".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS scrap_lista (
  id            bigserial PRIMARY KEY,
  nome          text NOT NULL,
  descricao     text,
  origem        text NOT NULL DEFAULT 'manual' CHECK (origem IN ('olx', 'manual', 'csv')),
  url_busca     text,
  cor           text NOT NULL DEFAULT '#6d28d9',
  ordem         integer NOT NULL DEFAULT 0,
  criado_por    text,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS scrap_anuncio (
  id                 bigserial PRIMARY KEY,
  lista_id           bigint NOT NULL REFERENCES scrap_lista(id) ON DELETE CASCADE,
  olx_id             bigint NOT NULL,
  titulo             text,
  preco              numeric,
  preco_texto        text,
  preco_antigo       text,
  categoria          text,
  tipo_negocio       text,
  subtipo            text,
  quartos            integer,
  banheiros          integer,
  vagas              integer,
  area_m2            numeric,
  condominio         numeric,
  iptu               numeric,
  bairro             text,
  cep                text,
  lat                double precision,
  lng                double precision,
  anunciante         text,
  anunciante_id      text,
  telefone_mascarado text,
  telefones          text[] NOT NULL DEFAULT '{}',
  descricao          text,
  fotos              text[] NOT NULL DEFAULT '{}',
  n_fotos            integer,
  url                text,
  data_olx           timestamptz,
  publicado_em       timestamptz,
  dados              jsonb NOT NULL DEFAULT '{}'::jsonb,
  coletado_em        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lista_id, olx_id)
);
CREATE INDEX IF NOT EXISTS scrap_anuncio_lista_idx ON scrap_anuncio (lista_id);
CREATE INDEX IF NOT EXISTS scrap_anuncio_telefones_idx ON scrap_anuncio USING gin (telefones);

CREATE TABLE IF NOT EXISTS scrap_contato (
  id             bigserial PRIMARY KEY,
  lista_id       bigint NOT NULL REFERENCES scrap_lista(id) ON DELETE CASCADE,
  nome           text,
  telefone       text NOT NULL,                       -- só dígitos, DDD + número (10 ou 11)
  empresa        text,
  origem         text NOT NULL DEFAULT 'olx' CHECK (origem IN ('olx', 'manual', 'csv')),
  anunciante_id  text,
  confirmado     boolean NOT NULL DEFAULT false,      -- o prefixo mascarado da OLX bate com o número
  n_anuncios     integer NOT NULL DEFAULT 0,
  bairros        text[] NOT NULL DEFAULT '{}',
  preco_min      numeric,
  preco_max      numeric,
  exemplo_url    text,
  exemplo_titulo text,
  status         text NOT NULL DEFAULT 'novo' CHECK (status IN ('novo', 'contatado', 'respondeu', 'interessado', 'descartado')),
  etiquetas      text[] NOT NULL DEFAULT '{}',
  observacao     text,
  dados          jsonb NOT NULL DEFAULT '{}'::jsonb,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (lista_id, telefone)
);
CREATE INDEX IF NOT EXISTS scrap_contato_telefone_idx ON scrap_contato (telefone);
CREATE INDEX IF NOT EXISTS scrap_contato_lista_status_idx ON scrap_contato (lista_id, status);

-- ---------------------------------------------------------------- telefone
-- "92 9998I-9200", "(92) 99170 4631", "99114.9501", "5592999819200" -> "92999819200". Lixo -> NULL.
--   11 dígitos: DDD válido e celular (3º dígito 9)         10 dígitos: só DDD 92/97 e fixo começando em 2 ou 3
--    9 dígitos começando em 9: ganha o 92                   8 dígitos começando em 2 ou 3: fixo de Manaus, ganha o 92
CREATE OR REPLACE FUNCTION scrap_telefone_normalizar(p text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE d text; ddd int; t text; i int;
BEGIN
  t := coalesce(p, '');
  FOR i IN 1..3 LOOP   -- "9998I-9200": letra no meio dos dígitos é dígito mal digitado
    t := regexp_replace(t, '(\d)[Il|]', '\11', 'g');
    t := regexp_replace(t, '[Il|](\d)', '1\1', 'g');
    t := regexp_replace(t, '(\d)[Oo](?=\d)', '\10', 'g');
  END LOOP;
  d := regexp_replace(t, '\D', '', 'g');
  IF d = '' THEN RETURN NULL; END IF;
  IF length(d) IN (12, 13) AND left(d, 2) = '55' THEN d := substr(d, 3); END IF;
  IF length(d) = 11 AND left(d, 1) = '0' THEN d := substr(d, 2); END IF;       -- 092 ...
  IF length(d) = 9 AND left(d, 1) = '9' THEN d := '92' || d; END IF;
  IF length(d) = 8 AND left(d, 1) IN ('2', '3') THEN d := '92' || d; END IF;
  IF length(d) NOT IN (10, 11) THEN RETURN NULL; END IF;
  ddd := left(d, 2)::int;
  IF ddd < 11 OR ddd > 99 OR substr(d, 2, 1) = '0' THEN RETURN NULL; END IF;
  IF length(d) = 11 THEN
    IF substr(d, 3, 1) <> '9' THEN RETURN NULL; END IF;
    IF substr(d, 3, 9) ~ '^(\d)\1{8}$' THEN RETURN NULL; END IF;                 -- 99999-9999
    RETURN d;
  END IF;
  IF ddd NOT IN (92, 97) OR substr(d, 3, 1) NOT IN ('2', '3') THEN RETURN NULL; END IF;
  RETURN d;
END
$function$;

CREATE OR REPLACE FUNCTION scrap_telefone_formatar(p text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $function$
  SELECT CASE WHEN p IS NULL THEN NULL
              WHEN length(p) = 11 THEN '(' || left(p, 2) || ') ' || substr(p, 3, 5) || '-' || substr(p, 8)
              WHEN length(p) = 10 THEN '(' || left(p, 2) || ') ' || substr(p, 3, 4) || '-' || substr(p, 7)
              ELSE p END
$function$;

-- os telefones que estão escritos num texto (descrição do anúncio). Conserta I/l/|->1 e O->0 entre dígitos.
CREATE OR REPLACE FUNCTION scrap_telefones_do_texto(p text)
RETURNS text[]
LANGUAGE plpgsql IMMUTABLE AS $function$
DECLARE t text; m text[]; achados text[] := '{}'; tel text; i int;
BEGIN
  t := coalesce(p, '');
  FOR i IN 1..3 LOOP
    t := regexp_replace(t, '(\d)[Il|]', '\11', 'g');
    t := regexp_replace(t, '[Il|](\d)', '1\1', 'g');
    t := regexp_replace(t, '(\d)[Oo](?=\d)', '\10', 'g');
  END LOOP;
  FOR m IN SELECT regexp_matches(t, '((?:\(?\d{2}\)?[\s.-]*)?\d{4,5}[\s.-]?\d{4})(?!\d)', 'g') LOOP
    tel := scrap_telefone_normalizar(m[1]);
    IF tel IS NOT NULL AND NOT (tel = ANY (achados)) THEN achados := achados || tel; END IF;
  END LOOP;
  RETURN achados;
END
$function$;

-- ---------------------------------------------------------------- os contatos nascem dos anúncios
-- Uma linha por telefone dentro da lista. Anúncio sem telefone não vira contato (Pedro: "tire os sem número").
-- Quem já existe guarda status, etiquetas e observação; só os números (quantos anúncios, bairros, faixa) são refeitos.
CREATE OR REPLACE FUNCTION scrap_contatos_rebuild(p_lista bigint)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n integer;
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
    FROM agr
  ON CONFLICT (lista_id, telefone) DO UPDATE SET
    nome = CASE WHEN c.origem = 'olx' THEN EXCLUDED.nome ELSE c.nome END,
    anunciante_id = coalesce(EXCLUDED.anunciante_id, c.anunciante_id),
    confirmado = c.confirmado OR EXCLUDED.confirmado,
    n_anuncios = EXCLUDED.n_anuncios, bairros = EXCLUDED.bairros,
    preco_min = EXCLUDED.preco_min, preco_max = EXCLUDED.preco_max,
    exemplo_url = EXCLUDED.exemplo_url, exemplo_titulo = EXCLUDED.exemplo_titulo,
    atualizado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE scrap_lista SET atualizado_em = now() WHERE id = p_lista;
  RETURN v_n;
END
$function$;

-- ---------------------------------------------------------------- as listas
CREATE OR REPLACE FUNCTION site_scrap_listas()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  SELECT jsonb_build_object(
    'listas', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'nome', l.nome, 'descricao', l.descricao, 'origem', l.origem, 'url_busca', l.url_busca, 'cor', l.cor,
        'ordem', l.ordem, 'criado_em', l.criado_em, 'atualizado_em', l.atualizado_em,
        'contatos', (SELECT count(*) FROM scrap_contato c WHERE c.lista_id = l.id),
        'por_status', (SELECT coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb) FROM (SELECT status, count(*) n FROM scrap_contato WHERE lista_id = l.id GROUP BY status) s),
        'anuncios', (SELECT count(*) FROM scrap_anuncio a WHERE a.lista_id = l.id),
        'anuncios_sem_telefone', (SELECT count(*) FROM scrap_anuncio a WHERE a.lista_id = l.id AND cardinality(a.telefones) = 0),
        'anunciantes', (SELECT count(DISTINCT coalesce(anunciante_id, anunciante)) FROM scrap_anuncio a WHERE a.lista_id = l.id),
        'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM scrap_contato WHERE lista_id = l.id) x)
      ) ORDER BY l.ordem, l.id) FROM scrap_lista l), '[]'::jsonb),
    'total_contatos', (SELECT count(*) FROM scrap_contato),
    'telefones_distintos', (SELECT count(DISTINCT telefone) FROM scrap_contato),
    'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM scrap_contato) x)
  )
$function$;

CREATE OR REPLACE FUNCTION site_scrap_lista_salvar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_nome text := nullif(trim(p->>'nome'), '');
BEGIN
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de um nome'); END IF;
  IF v_id IS NULL THEN
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por)
    VALUES (v_nome, nullif(trim(p->>'descricao'), ''), coalesce(nullif(p->>'origem', ''), 'manual'), nullif(trim(p->>'url_busca'), ''),
            coalesce(nullif(p->>'cor', ''), '#6d28d9'), coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem)
    RETURNING id INTO v_id;
  ELSE
    UPDATE scrap_lista SET nome = v_nome, descricao = coalesce(nullif(trim(p->>'descricao'), ''), descricao),
           url_busca = coalesce(nullif(trim(p->>'url_busca'), ''), url_busca), cor = coalesce(nullif(p->>'cor', ''), cor),
           ordem = coalesce((p->>'ordem')::int, ordem), atualizado_em = now()
     WHERE id = v_id;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

CREATE OR REPLACE FUNCTION site_scrap_lista_apagar(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM scrap_contato WHERE lista_id = p_id;
  DELETE FROM scrap_lista WHERE id = p_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  RETURN jsonb_build_object('ok', true, 'contatos_apagados', v_n);
END
$function$;

-- ---------------------------------------------------------------- os contatos
-- p_lista NULL = todas as listas, uma linha por telefone (com as listas em que ele está).
CREATE OR REPLACE FUNCTION site_scrap_contatos(p_lista bigint DEFAULT NULL, p_busca text DEFAULT NULL, p_status text DEFAULT NULL,
                                               p_etiqueta text DEFAULT NULL, p_bairro text DEFAULT NULL,
                                               p_ordem text DEFAULT 'anuncios', p_limite int DEFAULT 200, p_desloc int DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_busca text := nullif(trim(p_busca), ''); v_dig text; v_total int; v_itens jsonb; v_bairros jsonb;
BEGIN
  v_dig := nullif(regexp_replace(coalesce(v_busca, ''), '\D', '', 'g'), '');
  WITH base AS MATERIALIZED (
    SELECT c.*, l.nome AS lista_nome, l.cor AS lista_cor,
           (SELECT array_agg(DISTINCT l2.nome ORDER BY l2.nome) FROM scrap_contato c2 JOIN scrap_lista l2 ON l2.id = c2.lista_id
             WHERE c2.telefone = c.telefone AND c2.id <> c.id) AS tambem_em
      FROM scrap_contato c JOIN scrap_lista l ON l.id = c.lista_id
     WHERE (p_lista IS NULL OR c.lista_id = p_lista)
       AND (p_status IS NULL OR p_status = '' OR c.status = p_status)
       AND (p_etiqueta IS NULL OR p_etiqueta = '' OR p_etiqueta = ANY (c.etiquetas))
       AND (p_bairro IS NULL OR p_bairro = '' OR p_bairro = ANY (c.bairros))
       AND (v_busca IS NULL
            OR c.nome ILIKE '%' || v_busca || '%' OR c.empresa ILIKE '%' || v_busca || '%' OR c.observacao ILIKE '%' || v_busca || '%'
            OR c.exemplo_titulo ILIKE '%' || v_busca || '%'
            OR (v_dig IS NOT NULL AND c.telefone LIKE '%' || v_dig || '%'))
  ), uma AS (
    -- sem lista escolhida: um telefone só uma vez (fica a linha com mais anúncios)
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
    FROM (SELECT unnest(bairros) b, count(*) n FROM scrap_contato WHERE (p_lista IS NULL OR lista_id = p_lista) GROUP BY 1 ORDER BY 2 DESC LIMIT 40) y;
  RETURN jsonb_build_object('total', v_total, 'contatos', coalesce(v_itens, '[]'::jsonb), 'bairros', v_bairros);
END
$function$;

-- cria ou edita um contato (nome, telefone, empresa, status, etiquetas, observação, lista)
CREATE OR REPLACE FUNCTION site_scrap_contato_salvar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_tel text; v_lista bigint := nullif(p->>'lista_id', '')::bigint; v_et text[];
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
    INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, status, etiquetas, observacao, dados)
    VALUES (v_lista, v_tel, nullif(trim(p->>'nome'), ''), nullif(trim(p->>'empresa'), ''), 'manual',
            coalesce(nullif(p->>'status', ''), 'novo'), coalesce(v_et, '{}'), nullif(trim(p->>'observacao'), ''),
            jsonb_build_object('criado_por', p_quem))
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id, 'criado', true);
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
    origem = CASE WHEN p ? 'nome' AND origem = 'olx' THEN 'manual' ELSE origem END,   -- nome editado à mão não volta a ser refeito
    atualizado_em = now()
   WHERE id = v_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'contato não existe'); END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

-- ação em lote: status | etiqueta_por | etiqueta_tirar | mover | copiar | apagar
CREATE OR REPLACE FUNCTION site_scrap_contatos_acao(p_ids bigint[], p_acao text, p_valor text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int := 0; v_lista bigint; v_pulados int := 0;
BEGIN
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'nenhum contato escolhido'); END IF;
  CASE p_acao
    WHEN 'status' THEN
      IF p_valor NOT IN ('novo', 'contatado', 'respondeu', 'interessado', 'descartado') THEN RETURN jsonb_build_object('ok', false, 'erro', 'status inválido'); END IF;
      UPDATE scrap_contato SET status = p_valor, atualizado_em = now() WHERE id = ANY (p_ids);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'etiqueta_por' THEN
      IF nullif(trim(p_valor), '') IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga a etiqueta'); END IF;
      UPDATE scrap_contato SET etiquetas = array_append(etiquetas, trim(p_valor)), atualizado_em = now()
       WHERE id = ANY (p_ids) AND NOT (trim(p_valor) = ANY (etiquetas));
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'etiqueta_tirar' THEN
      UPDATE scrap_contato SET etiquetas = array_remove(etiquetas, trim(p_valor)), atualizado_em = now()
       WHERE id = ANY (p_ids) AND trim(p_valor) = ANY (etiquetas);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    WHEN 'mover', 'copiar' THEN
      v_lista := nullif(p_valor, '')::bigint;
      IF v_lista IS NULL OR NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = v_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista de destino não existe'); END IF;
      INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, anunciante_id, confirmado, n_anuncios, bairros, preco_min, preco_max,
                                 exemplo_url, exemplo_titulo, status, etiquetas, observacao, dados)
      SELECT v_lista, telefone, nome, empresa, CASE WHEN origem = 'olx' THEN 'manual' ELSE origem END, anunciante_id, confirmado, n_anuncios, bairros,
             preco_min, preco_max, exemplo_url, exemplo_titulo, status, etiquetas, observacao, dados || jsonb_build_object('veio_da_lista', lista_id)
        FROM scrap_contato WHERE id = ANY (p_ids) AND lista_id <> v_lista
      ON CONFLICT (lista_id, telefone) DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_pulados := cardinality(p_ids) - v_n;
      IF p_acao = 'mover' THEN DELETE FROM scrap_contato WHERE id = ANY (p_ids) AND lista_id <> v_lista; END IF;
    WHEN 'apagar' THEN
      DELETE FROM scrap_contato WHERE id = ANY (p_ids);
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSE
      RETURN jsonb_build_object('ok', false, 'erro', 'ação desconhecida: ' || coalesce(p_acao, ''));
  END CASE;
  RETURN jsonb_build_object('ok', true, 'n', v_n, 'pulados', v_pulados);
END
$function$;

-- os anúncios de um contato (gaveta): por telefone, em qualquer lista
CREATE OR REPLACE FUNCTION site_scrap_anuncios(p_telefone text, p_lista bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'olx_id', a.olx_id, 'titulo', a.titulo, 'preco', a.preco, 'preco_texto', a.preco_texto, 'categoria', a.categoria,
           'tipo_negocio', a.tipo_negocio, 'quartos', a.quartos, 'area_m2', a.area_m2, 'bairro', a.bairro, 'cep', a.cep,
           'anunciante', a.anunciante, 'telefones', (SELECT array_agg(scrap_telefone_formatar(t)) FROM unnest(a.telefones) t),
           'telefone_mascarado', a.telefone_mascarado, 'descricao', a.descricao, 'url', a.url, 'foto', a.fotos[1], 'n_fotos', a.n_fotos,
           'data_olx', a.data_olx, 'lista', l.nome) ORDER BY a.data_olx DESC NULLS LAST), '[]'::jsonb)
    FROM scrap_anuncio a JOIN scrap_lista l ON l.id = a.lista_id
   WHERE scrap_telefone_normalizar(p_telefone) = ANY (a.telefones)
     AND (p_lista IS NULL OR a.lista_id = p_lista)
$function$;

-- ---------------------------------------------------------------- a carga
-- {lista: {id?|nome, url_busca, descricao}, anuncios: [{olx_id, titulo, preco, ..., descricao, fotos: [...]}]}
-- Cria a lista se não existir (pelo nome), grava/atualiza os anúncios e refaz os contatos.
CREATE OR REPLACE FUNCTION site_scrap_importar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_lista bigint; v_nome text; v_n int; v_contatos int; v_sem int;
BEGIN
  v_lista := nullif(p->'lista'->>'id', '')::bigint;
  v_nome := nullif(trim(p->'lista'->>'nome'), '');
  IF v_lista IS NULL AND v_nome IS NOT NULL THEN SELECT id INTO v_lista FROM scrap_lista WHERE nome = v_nome LIMIT 1; END IF;
  IF v_lista IS NULL THEN
    IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de nome'); END IF;
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por)
    VALUES (v_nome, p->'lista'->>'descricao', 'olx', p->'lista'->>'url_busca', coalesce(nullif(p->'lista'->>'cor', ''), '#6d28d9'),
            coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem)
    RETURNING id INTO v_lista;
  ELSE
    UPDATE scrap_lista SET url_busca = coalesce(nullif(p->'lista'->>'url_busca', ''), url_busca), atualizado_em = now() WHERE id = v_lista;
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
  RETURN jsonb_build_object('ok', true, 'lista_id', v_lista, 'anuncios', v_n, 'contatos', v_contatos, 'anuncios_sem_telefone', v_sem);
END
$function$;

-- contatos digitados ou de CSV: [{nome, telefone, empresa, observacao, etiquetas}]
CREATE OR REPLACE FUNCTION site_scrap_importar_contatos(p_lista bigint, p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_n int; v_invalidos int; v_repetidos int; v_total int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = p_lista) THEN RETURN jsonb_build_object('ok', false, 'erro', 'lista não existe'); END IF;
  CREATE TEMP TABLE _entrada ON COMMIT DROP AS
    SELECT scrap_telefone_normalizar(x->>'telefone') AS telefone, nullif(trim(x->>'nome'), '') AS nome, nullif(trim(x->>'empresa'), '') AS empresa,
           nullif(trim(x->>'observacao'), '') AS observacao,
           coalesce((SELECT array_agg(DISTINCT trim(e)) FILTER (WHERE trim(e) <> '') FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(x->'etiquetas') = 'array' THEN x->'etiquetas' ELSE '[]'::jsonb END) e), '{}') AS etiquetas
      FROM jsonb_array_elements(coalesce(p, '[]'::jsonb)) x;
  SELECT count(*) INTO v_total FROM _entrada;
  SELECT count(*) INTO v_invalidos FROM _entrada WHERE telefone IS NULL;
  INSERT INTO scrap_contato (lista_id, telefone, nome, empresa, origem, observacao, etiquetas, dados)
  SELECT DISTINCT ON (telefone) p_lista, telefone, nome, empresa, 'csv', observacao, etiquetas, jsonb_build_object('criado_por', p_quem)
    FROM _entrada WHERE telefone IS NOT NULL ORDER BY telefone, nome NULLS LAST
  ON CONFLICT (lista_id, telefone) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_repetidos := v_total - v_invalidos - v_n;
  DROP TABLE _entrada;
  UPDATE scrap_lista SET atualizado_em = now() WHERE id = p_lista;
  RETURN jsonb_build_object('ok', true, 'inseridos', v_n, 'invalidos', v_invalidos, 'repetidos', v_repetidos);
END
$function$;

REVOKE ALL ON FUNCTION public.scrap_contatos_rebuild(bigint), public.site_scrap_listas(), public.site_scrap_lista_salvar(jsonb, text),
  public.site_scrap_lista_apagar(bigint), public.site_scrap_contatos(bigint, text, text, text, text, text, int, int),
  public.site_scrap_contato_salvar(jsonb, text), public.site_scrap_contatos_acao(bigint[], text, text), public.site_scrap_anuncios(text, bigint),
  public.site_scrap_importar(jsonb, text), public.site_scrap_importar_contatos(bigint, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.scrap_telefone_normalizar(text), public.scrap_telefone_formatar(text), public.scrap_telefones_do_texto(text),
  public.site_scrap_listas(), public.site_scrap_contatos(bigint, text, text, text, text, text, int, int), public.site_scrap_anuncios(text, bigint)
  TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_scrap_lista_salvar(jsonb, text), public.site_scrap_lista_apagar(bigint), public.site_scrap_contato_salvar(jsonb, text),
  public.site_scrap_contatos_acao(bigint[], text, text), public.site_scrap_importar(jsonb, text), public.site_scrap_importar_contatos(bigint, jsonb, text)
  TO nay_site_escrita;
COMMIT;
