-- 322 -- O cadastro de condomínio: criar e editar pela tela, e os condomínios do site antigo que ainda não tinham cadastro
--
-- Pedro, 08/10/2026: "quero uma aba nova adicionar condomínio, e que você puxe do site antigo todos os condomínios
-- mesmo sem imóvel ... quero o cadastro de condomínio no site normal aba imóveis e no crm também" e "todo condomínio
-- vai ter endereço fixo".
--
-- 1. `site_condominio_salvar(id, dados)`: a tela de cadastro. Sem id CRIA (nome obrigatório, sem repetir nome); com id
--    EDITA. Diferente do `site_condominio_guardar` (que só completa o que o cadastro de imóvel digitou), aqui o que a
--    pessoa escreveu VALE: campo que veio vazio apaga, e a lista de características substitui. Chave que não veio não
--    é tocada. Renomear o condomínio renomeia também os imóveis ligados a ele pelo id.
-- 2. Os condomínios que o site antigo já nos deu pelos imóveis (o nome está em `imoveis.condominio_nome`) e que não
--    tinham linha em `condominios` passam a ter. Ficam de fora os nomes que não são condomínio ("Condomínio não
--    identificado", "Casa", "Apartamento", "Prédio", "LIVRE"...). Nenhum imóvel é alterado.
--
-- O que FALTA e não dá para fazer daqui: os condomínios do site antigo que nunca tiveram imóvel só existem na lista
-- do admin de lá (/admin/condominios), atrás do login.
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

-- 2. os condomínios que o site antigo nos deu pelos imóveis e que ainda não tinham cadastro
WITH n AS (
  SELECT nay_chave_condominio(i.condominio_nome) AS k,
         mode() WITHIN GROUP (ORDER BY btrim(i.condominio_nome)) AS nome,
         mode() WITHIN GROUP (ORDER BY nullif(btrim(i.bairro), '')) AS bairro
    FROM imoveis i
   WHERE coalesce(btrim(i.condominio_nome), '') <> '' AND i.status IS DISTINCT FROM 'Excluído'
   GROUP BY 1
), novos AS (
  SELECT row_number() OVER (ORDER BY lower(unaccent(n.nome))) AS ordem, n.nome, n.bairro
    FROM n
   WHERE n.k <> '' AND length(n.nome) >= 3
     -- o que o site antigo escrevia no lugar do condomínio quando não havia um
     AND lower(unaccent(n.nome)) !~ '^(condominio )?(nao identificado|nao informado|sem condominio|casa|casa de condominio|casa de rua|apartamento|predio|livre|terreno|lote|sala|galpao|nenhum|outros?|rua|n/?a)$'
     AND NOT EXISTS (SELECT 1 FROM condominios c WHERE nay_chave_condominio(c.nome) = n.k)
     AND NOT EXISTS (SELECT 1 FROM condominios c WHERE lower(unaccent(btrim(c.nome))) = lower(unaccent(n.nome)))
)
INSERT INTO condominios (id, nome, bairro)
SELECT (SELECT max(id) FROM condominios) + ordem, nome, bairro FROM novos;

COMMIT;
