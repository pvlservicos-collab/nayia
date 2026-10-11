-- 346 -- O cadastro de condomínio grava a ficha completa (segurança, comodidades, taxas por quartos, ano,
--        complemento, observação) e a página pública do imóvel mostra o condomínio pela ficha dele
--
-- Pedro, 11/10/2026: as duas telas do site antigo (estrutura, lazer / segurança / comodidades e serviços, taxas de
-- condomínio e IPTU por quartos) na aba Condomínios do site novo; o imóvel só mostra o condomínio.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;

-- 1. site_condominio_salvar: os campos de texto novos, as duas listas novas e as taxas
SELECT pg_temp.remendar('site_condominio_salvar(integer,jsonb)',
$de$  FOREACH k IN ARRAY ARRAY['bairro', 'logradouro', 'numero', 'cidade', 'estado', 'cep', 'torres', 'andares',
                           'aptos_por_andar', 'elevador', 'unidades', 'construtora', 'revestimento'] LOOP
    CONTINUE WHEN NOT (p_dados ? k);
    v := left(nullif(btrim(coalesce(p_dados->>k, '')), ''), 200);$de$,
$para$  FOREACH k IN ARRAY ARRAY['bairro', 'logradouro', 'numero', 'cidade', 'estado', 'cep', 'torres', 'andares',
                           'aptos_por_andar', 'elevador', 'unidades', 'construtora', 'revestimento',
                           'ano_construcao', 'complemento', 'observacao'] LOOP   -- 346
    CONTINUE WHEN NOT (p_dados ? k);
    v := left(nullif(btrim(coalesce(p_dados->>k, '')), ''), CASE WHEN k = 'observacao' THEN 1000 ELSE 200 END);$para$);
SELECT pg_temp.remendar('site_condominio_salvar(integer,jsonb)',
$de$  -- as características do condomínio: a lista da tela substitui a que estava
  IF jsonb_typeof(p_dados->'lazer') = 'array' THEN
    SELECT coalesce(array_agg(s.x ORDER BY s.ord), '{}') INTO v_lazer
      FROM (SELECT DISTINCT ON (lower(btrim(a.t))) left(btrim(a.t), 80) AS x, a.ord
              FROM jsonb_array_elements_text(p_dados->'lazer') WITH ORDINALITY a(t, ord)
             WHERE btrim(a.t) <> ''
             ORDER BY lower(btrim(a.t)), a.ord) s;
    IF v_lazer IS DISTINCT FROM f.lazer THEN
      UPDATE condominio_ficha SET lazer = v_lazer WHERE id = f.id;
      v_mudou := array_append(v_mudou, 'lazer');
    END IF;
  END IF;$de$,
$para$  -- as características do condomínio, nas três listas (346): a lista da tela substitui a que estava
  FOREACH k IN ARRAY ARRAY['lazer', 'seguranca', 'comodidades'] LOOP
    CONTINUE WHEN coalesce(jsonb_typeof(p_dados->k), '') <> 'array';   -- chave ausente = não mexe
    SELECT coalesce(array_agg(s.x ORDER BY s.ord), '{}') INTO v_lazer
      FROM (SELECT DISTINCT ON (lower(btrim(a.t))) left(btrim(a.t), 80) AS x, a.ord
              FROM jsonb_array_elements_text(p_dados->k) WITH ORDINALITY a(t, ord)
             WHERE btrim(a.t) <> ''
             ORDER BY lower(btrim(a.t)), a.ord) s;
    IF v_lazer IS DISTINCT FROM (CASE k WHEN 'lazer' THEN f.lazer WHEN 'seguranca' THEN f.seguranca ELSE f.comodidades END) THEN
      EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING v_lazer, f.id;
      v_mudou := array_append(v_mudou, k);
    END IF;
  END LOOP;
  -- as taxas por quartos (ou metragem): condomínio fixo para todos daquele tamanho; IPTU quando for fixo
  IF jsonb_typeof(p_dados->'taxas') = 'array' THEN
    IF (SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                 'quartos', nullif(regexp_replace(coalesce(t->>'quartos', ''), '\D', '', 'g'), '')::int,
                 'metragem', nullif(regexp_replace(coalesce(t->>'metragem', ''), '[^0-9.,]', '', 'g'), ''),
                 'condominio', nullif(replace(regexp_replace(coalesce(t->>'condominio', ''), '[^0-9,.]', '', 'g'), ',', '.'), '')::numeric::float8,
                 'iptu', nullif(replace(regexp_replace(coalesce(t->>'iptu', ''), '[^0-9,.]', '', 'g'), ',', '.'), '')::numeric::float8)))
                 FILTER (WHERE coalesce(t->>'condominio', t->>'iptu', '') <> ''), '[]'::jsonb)
          FROM jsonb_array_elements(p_dados->'taxas') t) IS DISTINCT FROM f.taxas THEN
      UPDATE condominio_ficha SET taxas = (
        SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                 'quartos', nullif(regexp_replace(coalesce(t->>'quartos', ''), '\D', '', 'g'), '')::int,
                 'metragem', nullif(regexp_replace(coalesce(t->>'metragem', ''), '[^0-9.,]', '', 'g'), ''),
                 'condominio', nullif(replace(regexp_replace(coalesce(t->>'condominio', ''), '[^0-9,.]', '', 'g'), ',', '.'), '')::numeric::float8,
                 'iptu', nullif(replace(regexp_replace(coalesce(t->>'iptu', ''), '[^0-9,.]', '', 'g'), ',', '.'), '')::numeric::float8)))
                 FILTER (WHERE coalesce(t->>'condominio', t->>'iptu', '') <> ''), '[]'::jsonb)
          FROM jsonb_array_elements(p_dados->'taxas') t) WHERE id = f.id;
      v_mudou := array_append(v_mudou, 'taxas');
    END IF;
  END IF;$para$);

-- 2. a página pública do imóvel: o condomínio pela ficha dele, a observação e a mobília nos rótulos novos
SELECT pg_temp.remendar('site_imovel_publico(integer)',
$de$  ), condo AS (
    -- quais características são do CONDOMÍNIO: a lista do cadastro; na falta dela, a da ficha do anúncio
    SELECT coalesce(
             (SELECT array_agg(v) FROM t, jsonb_array_elements_text(
                 CASE WHEN jsonb_typeof(t.x -> 'caracteristicas do condominio') = 'array'
                      THEN t.x -> 'caracteristicas do condominio' ELSE '[]'::jsonb END) v),
             (SELECT f.caracteristicas_condominio FROM imovel_ficha f WHERE f.codigo = p_codigo),
             '{}'::text[]) AS tags
  )$de$,
$para$  ), condo AS (
    -- 346: as características do CONDOMÍNIO vêm da ficha dele (lazer, segurança, comodidades); sem ficha, as do anúncio
    SELECT coalesce(
             (SELECT nullif(cf.lazer || cf.seguranca || cf.comodidades, '{}') FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id),
             (SELECT f.caracteristicas_condominio FROM imovel_ficha f WHERE f.codigo = p_codigo),
             '{}'::text[]) AS tags,
           (SELECT jsonb_strip_nulls(jsonb_build_object('nome', cf.nome, 'tipo', cf.tipo, 'torres', cf.torres, 'andares', cf.andares,
                      'aptos_por_andar', cf.aptos_por_andar, 'elevador', cf.elevador, 'construtora', cf.construtora,
                      'ano', coalesce(cf.ano_construcao, cf.ano_lancamento::text), 'taxas', nullif(cf.taxas, '[]'::jsonb)))
              FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id) AS ficha
  )$para$);
SELECT pg_temp.remendar('site_imovel_publico(integer)',
$de$      'escadas', t.x ->> 'lances de escada', 'cobertura', t.x ->> 'tipo de cobertura'),
    'tagscondo', to_jsonb((SELECT tags FROM condo)),$de$,
$para$      'escadas', t.x ->> 'lances de escada',
      'cobertura', CASE WHEN t.cobertura THEN coalesce(t.x ->> 'tipo de cobertura', 'Sim') WHEN t.cobertura = false THEN NULL ELSE t.x ->> 'tipo de cobertura' END,
      'mobilia_nivel', nay_mobilia_nivel(t.mobilia)),
    'obs', t.observacao,
    'condo', (SELECT ficha FROM condo),
    'tagscondo', to_jsonb((SELECT tags FROM condo)),$para$);

COMMIT;
