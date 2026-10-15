-- 367 -- O que está incluso na taxa de condomínio: o cadastro grava, e as fichas já saem preenchidas
--
-- Pedro, 14/10/2026: "mexe lá na parte dos componentes do condomínio um campo O que está incluso na taxa de
-- condomínio. geralmente é: segurança 24 horas, água, gás, energia (só alguns flats). dá uma olhada em todos os
-- condomínios e põe essas coisas lá já nesse campo, que vai ficar mais fácil para a IA rodar".
-- A coluna é da 367a. Aqui:
-- 1. site_condominio_salvar grava a lista `taxa_inclui` como as outras três (a da tela substitui; ausente não mexe).
-- 2. O preenchimento, de dois jeitos e nada inventado:
--    a. "Segurança 24 horas" no condomínio cuja ficha já diz portaria / guarita / porteiro / vigilância / segurança /
--       central monitorada 24h (mercadinho 24h, recepção 24h e câmera sozinha não contam). Quem paga a portaria
--       24 horas é a taxa.
--    b. Água e gás só onde o anúncio de um imóvel de lá diz que a taxa inclui ("Condomínio: R$ 415,00 (inclui ÁGUA e
--       GÁS encanado)", "água e gás incluso na taxa de condomínio"...): 40 condomínios, lidos um a um em 14/10.
--       Ficaram de fora os que dizem "incluso no ALUGUEL" (Coral Gables, Morada dos Jardins, Mirante das Flores,
--       Ville de France, Reserva do Parque): ali é o aluguel que cobre, não a taxa. Total Ville Vida Nova: só água (o
--       anúncio diz que cada apartamento tem a sua botija). Onde o anúncio diz "segurança" incluída e a ficha não tem
--       24h, entra "Segurança".
--    Energia: nenhum anúncio diz que a taxa inclui energia, nem nos flats; fica para a equipe marcar.
-- Desfazer: UPDATE condominio_ficha SET taxa_inclui = '{}'; (a coluna é nova, nada mais foi tocado), e a função
-- volta pelo backup /root/backups-funcoes/site_condominio_salvar-2026-10-14-367.sql.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

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

-- o que os anúncios dizem que a taxa inclui (condominios.id -> itens; 'Segurança' só vale sem a de 24h na ficha)
CREATE TEMP TABLE t367_anuncio (cid integer PRIMARY KEY, itens text[] NOT NULL) ON COMMIT DROP;
INSERT INTO t367_anuncio VALUES
  (9,   '{Água,Gás}'),            -- Ideal Torquato, 4275: "condomínio R$ 207,42 (incluso água e gás)"
  (12,  '{Água,Gás}'),            -- Paradise Lake, 4916
  (17,  '{Água,Gás}'),            -- London Reserva Inglesa, 3913
  (33,  '{Gás}'),                 -- Smart Flores, 4112: "taxa de condomínio inclui gás"
  (58,  '{Segurança,Água,Gás}'),  -- Splendore Comfort Residence, 4231: "incluso água e gás, segurança 24 horas"
  (81,  '{Água}'),                -- Vitta Club House, 3672
  (96,  '{Água,Gás}'),            -- Acqua, 3682: "condomínio R$ 648,00 com água e gás"
  (100, '{Água,Gás}'),            -- Condomínio Harmonia, 4095 e 4103
  (111, '{Água,Gás}'),            -- Jardim Paradiso Antúrio, 4645
  (117, '{Gás}'),                 -- Turim Residencial, 9020
  (154, '{Segurança,Água,Gás}'),  -- Vila Jardim Lírios, 3917: "água e gás incluso na taxa, assim como segurança"
  (157, '{Água,Gás}'),            -- Total Ville Paraíso, 3763
  (178, '{Água,Gás}'),            -- Happy Days, 4394
  (186, '{Água,Gás}'),            -- Jardim Paradiso Alpínia, 3631 e 4052
  (188, '{Água}'),                -- Residencial Tapajós, 4169
  (194, '{Água,Gás}'),            -- Evidence Ponta Negra, 4559
  (196, '{Água,Gás}'),            -- Amazonas Flat, 3616
  (213, '{Água,Gás}'),            -- Reserva das Praias, 3172 e 4752
  (221, '{Água}'),                -- Praia dos Passarinhos, 4072
  (229, '{Água,Gás}'),            -- Weekend Club, 4551
  (236, '{Água,Gás}'),            -- Amazon Boulevard Life, 4746
  (240, '{Água,Gás}'),            -- Thiago de Mello, 3063
  (253, '{Segurança,Gás}'),       -- Smart Vista do Sol 2, 5177: "condomínio R$ 250,00 - com gás, segurança e lazer"
  (262, '{Água,Gás}'),            -- Singolare, 2835
  (275, '{Água}'),                -- Total Ville Vida Nova, 3780 (o gás é botija de cada um)
  (299, '{Água}'),                -- Vila dos Pássaros, 5762
  (302, '{Água,Gás}'),            -- Florença Park, 5196
  (328, '{Água}'),                -- Edifício Van Gogh, 3504
  (329, '{Água}'),                -- Edifício Simon Bolivar, 4915
  (338, '{Água}'),                -- Conquista Torquato, 5235
  (349, '{Gás}'),                 -- Leve Castanheiras, 4262
  (356, '{Segurança,Água}'),      -- Residencial Ponta Negra II, 3848: "(segurança + água inclusos)"
  (363, '{Água,Gás}'),            -- Saint Remy, 2984
  (371, '{Água,Gás}'),            -- Tropical Executive Hotel (flat), 3665
  (409, '{Água}'),                -- Condomínio Porto Tarumã, 3198
  (497, '{Segurança,Água,Gás}'),  -- Condomínio Residencial Veron, 3827, 3921 e 4037
  (520, '{Água}'),                -- Condomínio Passeio das Águas, 3611
  (567, '{Água}'),                -- Estoril, 4295
  (607, '{Água,Gás}'),            -- Condomínio Lírio, 3899 (não tinha ficha: a função cria)
  (678, '{Água}');                -- Edifício Boulevard Amazonas, 4020

-- a ficha que faltava (Condomínio Lírio) nasce pelo cadastro, como nasceria pela tela
SELECT site_condominio_salvar(a.cid, '{}'::jsonb)
  FROM t367_anuncio a WHERE NOT EXISTS (SELECT 1 FROM condominio_ficha f WHERE f.condominio_id = a.cid);

WITH base AS (
  SELECT f.id,
         EXISTS (SELECT 1 FROM unnest(f.seguranca) s
                  WHERE s ~ '24'
                    AND lower(unaccent(s)) ~ '(portaria|porteiro|guarita|seguranc|vigil|central monitorad|lobby.*monitorad|monitoramento)') AS seg24,
         a.itens
    FROM condominio_ficha f LEFT JOIN t367_anuncio a ON a.cid = f.condominio_id
   WHERE f.condominio_id IS NOT NULL AND f.taxa_inclui = '{}'
), lista AS (
  SELECT id,
         CASE WHEN seg24 THEN ARRAY['Segurança 24 horas']
              WHEN 'Segurança' = ANY (coalesce(itens, '{}')) THEN ARRAY['Segurança'] ELSE '{}' END
         || CASE WHEN 'Água' = ANY (coalesce(itens, '{}')) THEN ARRAY['Água'] ELSE '{}' END
         || CASE WHEN 'Gás' = ANY (coalesce(itens, '{}')) THEN ARRAY['Gás'] ELSE '{}' END AS nova
    FROM base
)
UPDATE condominio_ficha f SET taxa_inclui = l.nova, atualizado_em = now()
  FROM lista l WHERE l.id = f.id AND cardinality(l.nova) > 0;

-- conferência: ninguém com o anúncio ficou de fora
DO $$
DECLARE v_falta text;
BEGIN
  SELECT string_agg(a.cid::text, ', ') INTO v_falta
    FROM t367_anuncio a JOIN condominio_ficha f ON f.condominio_id = a.cid
   WHERE NOT (f.taxa_inclui && ARRAY['Água', 'Gás']);
  IF v_falta IS NOT NULL THEN RAISE EXCEPTION '367: ficou sem água/gás: %', v_falta; END IF;
  IF (SELECT count(*) FROM condominio_ficha WHERE condominio_id IN (SELECT cid FROM t367_anuncio)) <> 40 THEN
    RAISE EXCEPTION '367: esperava 40 fichas com anúncio';
  END IF;
END $$;

SELECT count(*) FILTER (WHERE taxa_inclui <> '{}') AS fichas_preenchidas,
       count(*) FILTER (WHERE 'Segurança 24 horas' = ANY (taxa_inclui)) AS seguranca_24h,
       count(*) FILTER (WHERE 'Segurança' = ANY (taxa_inclui)) AS seguranca_do_anuncio,
       count(*) FILTER (WHERE 'Água' = ANY (taxa_inclui)) AS agua,
       count(*) FILTER (WHERE 'Gás' = ANY (taxa_inclui)) AS gas
  FROM condominio_ficha;
COMMIT;
