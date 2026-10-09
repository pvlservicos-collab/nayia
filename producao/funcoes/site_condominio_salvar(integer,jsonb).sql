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
                           'aptos_por_andar', 'elevador', 'unidades', 'construtora', 'revestimento'] LOOP
    CONTINUE WHEN NOT (p_dados ? k);
    v := left(nullif(btrim(coalesce(p_dados->>k, '')), ''), 200);
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

  -- as características do condomínio: a lista da tela substitui a que estava
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
