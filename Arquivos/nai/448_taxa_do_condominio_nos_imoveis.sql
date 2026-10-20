-- 448 -- A taxa do condomínio (e o IPTU fixo dele) vai para os imóveis; o que a taxa inclui aparece na página do imóvel
--
-- Pedro, 20/10/2026: "quando cadastrado no condomínio a taxa de condomínio e o que vem incluso não está atualizando no
-- imóvel, pode verificar isso por gentileza, vê certinho para quando eu alterar um condomínio ele já ir para todas as
-- páginas".
--
-- O que estava: o cadastro do condomínio grava a taxa por quartos em condominio_ficha.taxas (344) e o "incluso" em
-- condominio_ficha.taxa_inclui (367), e só ali. Todas as telas que mostram a taxa do IMÓVEL (página do site, card, Nay
-- velha e nova, anúncio da OLX, CRM, popup) leem imoveis.taxa_condominio, que ninguém atualizava. Ex.: Residencial
-- Tarumã 3 quartos = R$ 300 na ficha, e os imóveis de 3 quartos dele (5735, 331, 3349) sem taxa; Vista dos Cedros
-- 2 quartos = R$ 550 e o 5743 com R$ 700.
-- E um erro de leitura: "3.200" virava 3,2 (o ponto de milhar lido como decimal). Atlantis, Lê Boulevard e Walderez
-- Simões ficaram com 1,621 / 1,265 / 3,2.
--
-- Como fica:
--   1. site_condominio_salvar lê o valor com captacao_numero ("3.200" = 3200, "550,50" = 550,5); os três estragados
--      são consertados (x 1000).
--   2. condominio_taxa_aos_imoveis(ficha): para cada linha de taxa (quartos + valor), o valor vai para TODO imóvel do
--      condomínio com aquele número de quartos (ligado pelo id, ou só pelo nome quando não tem id), menos o Excluído.
--      O IPTU vai junto só quando a linha do condomínio tem IPTU (o IPTU fixo). O condomínio manda: salvar o condomínio
--      escreve por cima do que o imóvel tinha. Exceção: as 90 linhas que uma migração antiga DEDUZIU dos próprios
--      imóveis ("fonte": "imóveis") só preenchem imóvel sem taxa; ao salvar o condomínio na tela, a linha vira digitada.
--      Gatilho condominio_taxa_aos_imoveis_tg: roda sempre que as taxas, o id ou os nomes da ficha mudam.
--   3. imovel novo, que troca de condomínio ou de quartos, ou que está sem taxa: pega a taxa da ficha
--      (gatilho imoveis_aa_taxa_do_condominio, antes do carimbo da taxa).
--   4. site_imovel_publico manda o "incluso" (taxa_inclui) junto da ficha do condomínio, para a página do imóvel.
--      O editar do admin e o popup já liam da ficha; a Nay nova (nay-core repo.ficha) também.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.site_condominio_salvar(p_id integer, p_dados jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_ligados int := 0;
  c        record;
  f        condominio_ficha%ROWTYPE;
  v_nome   text := left(nullif(btrim(regexp_replace(coalesce(p_dados->>'nome', ''), '\s+', ' ', 'g')), ''), 160);
  v_bairro text := left(nullif(btrim(coalesce(p_dados->>'bairro', '')), ''), 200);
  v_criado boolean := false;
  v_mudou  text[] := '{}';
  v_igual  integer;
  v_ano    integer;
  v_lazer  text[];
  v_n      integer;
  k        text;
  v        text;
BEGIN
  IF p_dados IS NULL OR jsonb_typeof(p_dados) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'faltaram os dados do condomínio');
  END IF;
  -- duas pessoas cadastrando ao mesmo tempo: uma de cada vez (o id é o maior + 1)
  PERFORM pg_advisory_xact_lock(hashtext('cadastro de condominio'));

  IF p_id IS NULL THEN
    IF v_nome IS NULL OR length(v_nome) < 3 THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'escreva o nome do condomínio');
    END IF;
  ELSE
    SELECT x.id, x.nome, x.bairro INTO c FROM condominios x WHERE x.id = p_id;
    IF c.id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'condomínio não encontrado');
    END IF;
    IF p_dados ? 'nome' AND (v_nome IS NULL OR length(v_nome) < 3) THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'o nome do condomínio não pode ficar vazio');
    END IF;
  END IF;

  IF v_nome IS NOT NULL THEN
    SELECT x.id INTO v_igual FROM condominios x
     WHERE lower(unaccent(btrim(x.nome))) = lower(unaccent(v_nome)) AND x.id IS DISTINCT FROM p_id
     ORDER BY x.id LIMIT 1;
    IF v_igual IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'já existe um condomínio com esse nome', 'id', v_igual);
    END IF;
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO condominios (id, nome, bairro)
    VALUES ((SELECT coalesce(max(x.id), 0) + 1 FROM condominios x), v_nome, v_bairro)
    RETURNING id, nome, bairro INTO c;
    v_criado := true;
  ELSE
    IF v_nome IS NOT NULL AND v_nome IS DISTINCT FROM c.nome THEN
      UPDATE condominios SET nome = v_nome WHERE id = c.id;
      -- o imóvel ligado pelo id mostra o nome do condomínio: acompanha
      UPDATE imoveis SET condominio_nome = v_nome WHERE condo_id = c.id AND condominio_nome IS DISTINCT FROM v_nome;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      -- 328: o imóvel ligado só pelo nome VELHO (sem condo_id) vai junto, e passa a ficar ligado pelo id
      UPDATE imoveis SET condo_id = c.id, condominio_nome = v_nome
       WHERE condo_id IS NULL AND lower(unaccent(btrim(condominio_nome))) = lower(unaccent(btrim(c.nome)));
      GET DIAGNOSTICS v_ligados = ROW_COUNT;
      v_n := v_n + v_ligados;
      v_mudou := array_append(v_mudou, 'nome');
      c.nome := v_nome;
    END IF;
    IF p_dados ? 'bairro' AND v_bairro IS DISTINCT FROM c.bairro THEN
      UPDATE condominios SET bairro = v_bairro WHERE id = c.id;
      c.bairro := v_bairro;
    END IF;
  END IF;

  -- a ficha: a que já é dele, uma solta com o mesmo nome, ou uma nova
  SELECT * INTO f FROM condominio_ficha WHERE condominio_id = c.id;
  IF f.id IS NULL THEN
    UPDATE condominio_ficha SET condominio_id = c.id
     WHERE id = (SELECT x.id FROM condominio_ficha x
                  WHERE x.condominio_id IS NULL AND lower(x.nome) = lower(c.nome) LIMIT 1)
    RETURNING * INTO f;
  END IF;
  IF f.id IS NULL THEN
    BEGIN
      INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
      VALUES (c.id, c.nome, c.bairro, 'cadastro de condomínio') RETURNING * INTO f;
    EXCEPTION WHEN unique_violation THEN   -- uma ficha de outro condomínio já usa este nome
      INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
      VALUES (c.id, c.nome || ' (' || c.id || ')', c.bairro, 'cadastro de condomínio') RETURNING * INTO f;
    END;
  END IF;
  IF f.nome IS DISTINCT FROM c.nome AND f.nome IS DISTINCT FROM c.nome || ' (' || c.id || ')' THEN
    BEGIN
      UPDATE condominio_ficha SET nome = c.nome WHERE id = f.id;
    EXCEPTION WHEN unique_violation THEN
      UPDATE condominio_ficha SET nome = c.nome || ' (' || c.id || ')' WHERE id = f.id;
    END;
  END IF;

  IF p_dados->>'tipo' IN ('apartamentos', 'casas_lotes') AND f.tipo IS DISTINCT FROM p_dados->>'tipo' THEN
    UPDATE condominio_ficha SET tipo = p_dados->>'tipo' WHERE id = f.id;
    v_mudou := array_append(v_mudou, 'tipo');
  END IF;

  -- os campos de texto: a chave que veio VALE (vazia apaga); a que não veio não é tocada
  FOREACH k IN ARRAY ARRAY['bairro', 'logradouro', 'numero', 'cidade', 'estado', 'cep', 'torres', 'andares',
                           'aptos_por_andar', 'elevador', 'unidades', 'construtora', 'revestimento',
                           'ano_construcao', 'complemento', 'observacao'] LOOP   -- 346
    CONTINUE WHEN NOT (p_dados ? k);
    v := left(nullif(btrim(coalesce(p_dados->>k, '')), ''), CASE WHEN k = 'observacao' THEN 1000 ELSE 200 END);
    IF v IS DISTINCT FROM (to_jsonb(f)->>k) THEN
      EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING v, f.id;
      v_mudou := array_append(v_mudou, k);
    END IF;
  END LOOP;

  IF p_dados ? 'ano_lancamento' THEN
    v := nullif(regexp_replace(coalesce(p_dados->>'ano_lancamento', ''), '\D', '', 'g'), '');
    v_ano := CASE WHEN v ~ '^\d{4}$' AND v::int BETWEEN 1900 AND 2100 THEN v::int END;
    IF v IS NOT NULL AND v_ano IS NULL THEN
      RAISE EXCEPTION 'ano de lançamento inválido: %', left(p_dados->>'ano_lancamento', 20);
    END IF;
    IF v_ano IS DISTINCT FROM f.ano_lancamento THEN
      UPDATE condominio_ficha SET ano_lancamento = v_ano WHERE id = f.id;
      v_mudou := array_append(v_mudou, 'ano_lancamento');
    END IF;
  END IF;

  -- as características do condomínio, nas três listas (346), e o que a taxa inclui (367):
  -- a lista da tela substitui a que estava
  FOREACH k IN ARRAY ARRAY['lazer', 'seguranca', 'comodidades', 'taxa_inclui'] LOOP
    CONTINUE WHEN coalesce(jsonb_typeof(p_dados->k), '') <> 'array';   -- chave ausente = não mexe
    SELECT coalesce(array_agg(s.x ORDER BY s.ord), '{}') INTO v_lazer
      FROM (SELECT DISTINCT ON (lower(btrim(a.t))) left(btrim(a.t), 80) AS x, a.ord
              FROM jsonb_array_elements_text(p_dados->k) WITH ORDINALITY a(t, ord)
             WHERE btrim(a.t) <> ''
             ORDER BY lower(btrim(a.t)), a.ord) s;
    IF v_lazer IS DISTINCT FROM (CASE k WHEN 'lazer' THEN f.lazer WHEN 'seguranca' THEN f.seguranca
                                        WHEN 'taxa_inclui' THEN f.taxa_inclui ELSE f.comodidades END) THEN
      EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING v_lazer, f.id;
      v_mudou := array_append(v_mudou, k);
    END IF;
  END LOOP;
  -- as taxas por quartos (ou metragem): condomínio fixo para todos daquele tamanho; IPTU quando for fixo
  -- 448: o valor em reais como se escreve aqui ("3.200" = 3200, "550,50" = 550,5); o gatilho leva aos imóveis
  IF jsonb_typeof(p_dados->'taxas') = 'array' THEN
    IF (SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                 'quartos', nullif(regexp_replace(coalesce(t->>'quartos', ''), '\D', '', 'g'), '')::int,
                 'metragem', nullif(regexp_replace(coalesce(t->>'metragem', ''), '[^0-9.,]', '', 'g'), ''),
                 'condominio', captacao_numero(t->>'condominio')::float8,
                 'iptu', captacao_numero(t->>'iptu')::float8)))
                 FILTER (WHERE coalesce(t->>'condominio', t->>'iptu', '') <> ''), '[]'::jsonb)
          FROM jsonb_array_elements(p_dados->'taxas') t) IS DISTINCT FROM f.taxas THEN
      UPDATE condominio_ficha SET taxas = (
        SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                 'quartos', nullif(regexp_replace(coalesce(t->>'quartos', ''), '\D', '', 'g'), '')::int,
                 'metragem', nullif(regexp_replace(coalesce(t->>'metragem', ''), '[^0-9.,]', '', 'g'), ''),
                 'condominio', captacao_numero(t->>'condominio')::float8,
                 'iptu', captacao_numero(t->>'iptu')::float8)))
                 FILTER (WHERE coalesce(t->>'condominio', t->>'iptu', '') <> ''), '[]'::jsonb)
          FROM jsonb_array_elements(p_dados->'taxas') t) WHERE id = f.id;
      v_mudou := array_append(v_mudou, 'taxas');
    END IF;
  END IF;

  IF v_criado OR cardinality(v_mudou) > 0 THEN
    -- o endereço num texto só (é o que o CRM e a captação leem) acompanha os campos
    UPDATE condominio_ficha x
       SET atualizado_em = now(),
           endereco = CASE WHEN coalesce(x.logradouro, '') <> ''
                           THEN x.logradouro || coalesce(', nº ' || nullif(x.numero, ''), '')
                                || coalesce(', Bairro ' || nullif(coalesce(x.bairro, c.bairro), ''), '')
                                || coalesce(', ' || nullif(x.cidade, ''), '') || coalesce(' - ' || nullif(x.estado, ''), '')
                           ELSE x.endereco END
     WHERE x.id = f.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', c.id, 'nome', c.nome, 'criado', v_criado, 'mudou', to_jsonb(v_mudou),
                            'imoveis_renomeados', coalesce(v_n, 0));
END;
$function$;

-- os três que o ponto de milhar estragou (conferidos em 20/10: só eles têm taxa < 100 ou IPTU < 20)
UPDATE condominio_ficha cf
   SET taxas = (SELECT jsonb_agg(CASE
                   WHEN (t->>'condominio')::numeric < 100 OR (t->>'iptu')::numeric < 20 THEN
                     t || jsonb_strip_nulls(jsonb_build_object(
                            'condominio', CASE WHEN (t->>'condominio')::numeric < 100 THEN round((t->>'condominio')::numeric * 1000)::float8 END,
                            'iptu', CASE WHEN (t->>'iptu')::numeric < 20 THEN round((t->>'iptu')::numeric * 1000)::float8 END))
                   ELSE t END ORDER BY o)
                  FROM jsonb_array_elements(cf.taxas) WITH ORDINALITY x(t, o))
 WHERE cf.id IN (699, 751, 753);

-- a taxa (e o IPTU fixo) da ficha do condomínio nos imóveis dele, pelo número de quartos
CREATE OR REPLACE FUNCTION public.condominio_taxa_aos_imoveis(p_ficha integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE n int := 0; m int := 0;
BEGIN
  WITH cf AS (
    SELECT f.id, f.condominio_id, f.taxas,
           array_remove(ARRAY[lower(btrim(f.nome)), lower(btrim(c.nome))]
                        || coalesce((SELECT array_agg(lower(btrim(x))) FROM unnest(f.nomes_no_imovel) x), '{}'), NULL) AS nomes
      FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id
     WHERE f.id = p_ficha
  ), linha AS (   -- uma linha por número de quartos (a primeira, se repetir)
    SELECT DISTINCT ON ((t->>'quartos')::int) (t->>'quartos')::int AS quartos,
           (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu,
           t ? 'fonte' AS deduzida   -- a linha que uma migração tirou dos próprios imóveis, não digitada
      FROM cf, jsonb_array_elements(cf.taxas) WITH ORDINALITY x(t, o)
     WHERE t->>'quartos' ~ '^\d+$' AND coalesce(t->>'condominio', t->>'iptu') IS NOT NULL
     ORDER BY (t->>'quartos')::int, o
  ), alvo AS (
    -- a taxa DIGITADA no condomínio manda; a deduzida só preenche quem está sem
    SELECT i.codigo,
           CASE WHEN l.deduzida AND i.taxa_condominio IS NOT NULL THEN i.taxa_condominio
                ELSE coalesce(l.condominio, i.taxa_condominio) END AS taxa,
           CASE WHEN l.deduzida AND i.iptu IS NOT NULL THEN i.iptu ELSE coalesce(l.iptu, i.iptu) END AS iptu
      FROM imoveis i, cf, linha l
     WHERE i.quartos = l.quartos AND coalesce(i.status, '') <> 'Excluído'
       AND (i.condo_id = cf.condominio_id
            OR (i.condo_id IS NULL AND lower(btrim(coalesce(i.condominio_nome, ''))) = ANY (cf.nomes)))
  )
  UPDATE imoveis i SET taxa_condominio = a.taxa, iptu = a.iptu
    FROM alvo a WHERE i.codigo = a.codigo AND (i.taxa_condominio IS DISTINCT FROM a.taxa OR i.iptu IS DISTINCT FROM a.iptu);
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION public.condominio_taxa_aos_imoveis_tg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.taxas IS DISTINCT FROM OLD.taxas OR NEW.condominio_id IS DISTINCT FROM OLD.condominio_id
     OR NEW.nome IS DISTINCT FROM OLD.nome OR NEW.nomes_no_imovel IS DISTINCT FROM OLD.nomes_no_imovel THEN
    PERFORM condominio_taxa_aos_imoveis(NEW.id);
  END IF;
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS condominio_taxa_aos_imoveis_tg ON condominio_ficha;
CREATE TRIGGER condominio_taxa_aos_imoveis_tg AFTER INSERT OR UPDATE ON condominio_ficha
  FOR EACH ROW EXECUTE FUNCTION condominio_taxa_aos_imoveis_tg();

-- o imóvel que entra num condomínio (novo, troca de condomínio ou de quartos, ou sem taxa) pega a taxa da ficha.
-- Roda antes de imoveis_carimbar_taxa (ordem alfabética), e carimba ele mesmo: o carimbo só dispara quando a taxa está
-- no SET do comando, e aqui quem escreve é o gatilho.
CREATE OR REPLACE FUNCTION public.imoveis_taxa_do_condominio()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE l record;
BEGIN
  IF coalesce(NEW.quartos, 0) <= 0 OR coalesce(NEW.status, '') = 'Excluído' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.condo_id IS NOT DISTINCT FROM OLD.condo_id AND NEW.quartos IS NOT DISTINCT FROM OLD.quartos
     AND NEW.condominio_nome IS NOT DISTINCT FROM OLD.condominio_nome AND NEW.taxa_condominio IS NOT NULL THEN
    RETURN NEW;
  END IF;
  SELECT (t->>'condominio')::numeric AS condominio, (t->>'iptu')::numeric AS iptu INTO l
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id,
         jsonb_array_elements(f.taxas) WITH ORDINALITY x(t, o)
   WHERE t->>'quartos' = NEW.quartos::text
     AND (f.condominio_id = NEW.condo_id
          OR (NEW.condo_id IS NULL AND lower(btrim(coalesce(NEW.condominio_nome, ''))) <> ''
              AND lower(btrim(NEW.condominio_nome)) IN (lower(btrim(f.nome)), lower(btrim(c.nome)))))
   ORDER BY (f.condominio_id = NEW.condo_id) DESC NULLS LAST, o
   LIMIT 1;
  IF l.condominio IS NOT NULL AND NEW.taxa_condominio IS DISTINCT FROM l.condominio THEN
    NEW.taxa_condominio := l.condominio;
    NEW.taxa_condominio_em := now();
  END IF;
  IF l.iptu IS NOT NULL THEN
    NEW.iptu := l.iptu;
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS imoveis_aa_taxa_do_condominio ON imoveis;
CREATE TRIGGER imoveis_aa_taxa_do_condominio BEFORE INSERT OR UPDATE OF condo_id, condominio_nome, quartos, taxa_condominio, status
  ON imoveis FOR EACH ROW EXECUTE FUNCTION imoveis_taxa_do_condominio();

-- a primeira passada: todas as fichas que têm taxa
SELECT count(*) AS fichas, sum(condominio_taxa_aos_imoveis(id)) AS imoveis_atualizados
  FROM condominio_ficha WHERE taxas <> '[]'::jsonb;

CREATE OR REPLACE FUNCTION public.site_imovel_publico(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH i AS (
    SELECT im.*, coalesce(im.extras, '{}'::jsonb) AS x,
           initcap(split_part(coalesce(im.tipo, 'Imóvel'), ' ', 1)) AS tipo_curto
      FROM imoveis im
     WHERE im.codigo = p_codigo AND im.publicado_no_site AND im.disponivel AND NOT coalesce(im.bloqueado, false)
  ), t AS (
    SELECT i.*, coalesce(nullif(btrim(i.tipo), ''), 'Imóvel')
           || CASE WHEN coalesce(i.quartos, 0) > 0 THEN ' ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
           || CASE WHEN nullif(btrim(i.condominio_nome), '') IS NOT NULL THEN ' no ' || btrim(i.condominio_nome)
                   WHEN nullif(btrim(i.bairro), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END AS titulo
      FROM i
  ), condo AS (
    -- 346: as características do CONDOMÍNIO vêm da ficha dele (lazer, segurança, comodidades); sem ficha, as do anúncio
    SELECT coalesce(
             (SELECT nullif(cf.lazer || cf.seguranca || cf.comodidades, '{}') FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id),
             (SELECT f.caracteristicas_condominio FROM imovel_ficha f WHERE f.codigo = p_codigo),
             '{}'::text[]) AS tags,
           (SELECT jsonb_strip_nulls(jsonb_build_object('nome', cf.nome, 'tipo', cf.tipo, 'torres', cf.torres, 'andares', cf.andares,
                      'aptos_por_andar', cf.aptos_por_andar, 'elevador', cf.elevador, 'construtora', cf.construtora,
                      'ano', coalesce(cf.ano_construcao, cf.ano_lancamento::text), 'taxas', nullif(cf.taxas, '[]'::jsonb),
                      'taxa_inclui', nullif(to_jsonb(cf.taxa_inclui), '[]'::jsonb)))   -- 448: o que a taxa inclui
              FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id) AS ficha
  )
  SELECT jsonb_build_object(
    'codigo', t.codigo,
    'titulo', t.titulo,
    'slug', btrim(regexp_replace(lower(nay_sem_acento(t.titulo)), '[^a-z0-9]+', '-', 'g'), '-'),
    'parceiro', coalesce(t.e_parceiro, false),
    -- imóvel de parceiro não sai pela caixa (parceria nunca sai): a página nem oferece o envio
    'pode_enviar', NOT coalesce(t.e_parceiro, false),
    'local', jsonb_build_object('condominio', nullif(btrim(t.condominio_nome), ''), 'bairro', t.bairro,
                                'cidade', coalesce(t.cidade, 'Manaus'), 'estado', coalesce(t.estado, 'AM')),
    'carac', jsonb_build_object(
      'tipo', t.tipo, 'quartos', t.quartos, 'suites', t.suites, 'banheiros', t.banheiros,
      'salas', t.x ->> 'salas', 'vagas', t.vagas, 'vagascob', t.vagas_cobertas,
      'mobilia', t.mobilia, 'face', t.sol,
      'areautil', t.area_util, 'areatotal', t.area_total, 'areacons', t.x ->> 'area construida',
      'terreno', t.x ->> 'tamanho do terreno', 'frente', t.x ->> 'frente', 'fundo', t.x ->> 'fundo',
      'pedireito', t.x ->> 'pe direito', 'andares', t.x ->> 'andares', 'elevadores', t.x ->> 'elevadores',
      'escadas', t.x ->> 'lances de escada',
      'cobertura', CASE WHEN t.cobertura THEN coalesce(t.x ->> 'tipo de cobertura', 'Sim') WHEN t.cobertura = false THEN NULL ELSE t.x ->> 'tipo de cobertura' END,
      'mobilia_nivel', nay_mobilia_nivel(t.mobilia)),
    'obs', t.observacao,
    'condo', (SELECT ficha FROM condo),
    'tagscondo', to_jsonb((SELECT tags FROM condo)),
    'tagsimovel', to_jsonb(coalesce(
        (SELECT array_agg(c) FROM unnest(coalesce(nullif(t.caracteristicas, '{}'),
                 (SELECT f.caracteristicas_imovel FROM imovel_ficha f WHERE f.codigo = p_codigo), '{}'::text[])) c
          WHERE NOT EXISTS (SELECT 1 FROM condo, unnest(condo.tags) ct WHERE ct = c)), '{}'::text[])),
    'valores', jsonb_build_object('aluguel', t.valor_aluguel, 'venda', t.valor_venda, 'condo', t.taxa_condominio,
                                  'iptu', t.iptu, 'fin', t.x ->> 'aceita financiamento', 'permuta', t.x ->> 'permuta'),
    'incluso', t.x ->> 'incluso no aluguel',
    'garantia', t.x ->> 'garantia de aluguel',
    'desc', t.descricao,
    'fotos', coalesce((SELECT jsonb_agg(f.url ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id)
                         FROM imovel_fotos f
                        WHERE f.codigo = p_codigo AND coalesce(f.url, '') <> '' AND NOT coalesce(f.e_mosaico, false)), '[]'::jsonb),
    -- a posição vai ARREDONDADA (3 casas, ~110 m): a página mostra a região, não a porta
    'geo', (SELECT jsonb_build_object('lat', round(g.lat::numeric, 3), 'lon', round(g.lon::numeric, 3), 'precisao', g.precisao)
              FROM imovel_geo g WHERE g.codigo = p_codigo)
  ) FROM t;
$function$;

COMMIT;
