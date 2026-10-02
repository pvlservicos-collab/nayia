-- 273 (02/10/2026): O CONDOMÍNIO GUARDA OS PRÓPRIOS DADOS; O IMÓVEL SÓ PUXA.
--
-- Pedro, 02/10: "não quero ter que digitar a mesma informação 2 vezes"
--   - "andar não precisa"
--   - "quando selecionei condomínio não puxou o número"
--   - "no cadastro já cadastra direto as informações de condomínio, porque hoje estou colocando
--      uma aba a mais sendo que as informações do condomínio já são fixas, pode separar de fato"
--
-- Até hoje a tabela `condominios` tinha só nome e bairro. O endereço que o cadastro "puxava" era
-- a rua mais comum entre os imóveis já ligados (sem número, sem CEP), e só 11 condomínios tinham
-- ficha (`condominio_ficha`), com o endereço num texto só.
--
-- Agora:
--   1. `condominio_ficha` ganha o endereço em campos: logradouro, numero, cidade, estado, cep.
--   2. `site_condominio_guardar`: o que se digita no cadastro de um imóvel (endereço, número, CEP,
--      andares, elevadores, características do condomínio) fica guardado NO CONDOMÍNIO. O próximo
--      imóvel do mesmo condomínio já nasce com tudo. Campo vazio nunca apaga; característica só
--      se acrescenta (tirar uma do imóvel não tira do condomínio).
--   3. O andar sai da régua do cadastro (`nai_imovel_pontos`): não é mais cobrado como "falta".
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE public.condominio_ficha
  ADD COLUMN IF NOT EXISTS logradouro text,
  ADD COLUMN IF NOT EXISTS numero     text,
  ADD COLUMN IF NOT EXISTS cidade     text,
  ADD COLUMN IF NOT EXISTS estado     text,
  ADD COLUMN IF NOT EXISTS cep        text;

CREATE OR REPLACE FUNCTION public.site_condominio_guardar(p_condo integer, p_dados jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c        record;
  f        condominio_ficha%ROWTYPE;
  v_mudou  text[] := '{}';
  k        text;
  v        text;
  n        integer;
  v_atual  integer;
  v_novos  text[];
BEGIN
  SELECT id, nome, bairro INTO c FROM condominios WHERE id = p_condo;
  IF c.id IS NULL OR p_dados IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'condominio nao existe');
  END IF;

  -- a ficha do condomínio: a que já é dele, uma solta com o mesmo nome, ou uma nova
  SELECT * INTO f FROM condominio_ficha WHERE condominio_id = p_condo;
  IF f.id IS NULL THEN
    UPDATE condominio_ficha SET condominio_id = p_condo
     WHERE id = (SELECT x.id FROM condominio_ficha x
                  WHERE x.condominio_id IS NULL AND lower(x.nome) = lower(c.nome) LIMIT 1)
    RETURNING * INTO f;
  END IF;
  IF f.id IS NULL THEN
    BEGIN
      INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
      VALUES (p_condo, c.nome, c.bairro, 'cadastro de imóvel') RETURNING * INTO f;
    EXCEPTION WHEN unique_violation THEN   -- dois condomínios com o mesmo nome
      INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
      VALUES (p_condo, c.nome || ' (' || p_condo || ')', c.bairro, 'cadastro de imóvel') RETURNING * INTO f;
    END;
  END IF;

  -- o endereço: campo vazio num imóvel NÃO apaga o dado do condomínio
  FOREACH k IN ARRAY ARRAY['logradouro', 'numero', 'bairro', 'cidade', 'estado', 'cep'] LOOP
    v := left(nullif(btrim(coalesce(p_dados->>k, '')), ''), 200);
    CONTINUE WHEN v IS NULL;
    IF v IS DISTINCT FROM (to_jsonb(f)->>k) THEN
      EXECUTE format('UPDATE condominio_ficha SET %I = $1 WHERE id = $2', k) USING v, f.id;
      v_mudou := v_mudou || k;
    END IF;
  END LOOP;
  IF c.bairro IS NULL AND 'bairro' = ANY (v_mudou) THEN
    UPDATE condominios SET bairro = left(btrim(p_dados->>'bairro'), 200) WHERE id = p_condo;
  END IF;

  -- andares e elevadores são do PRÉDIO: só quando o imóvel é de prédio (numa casa, "andares" é da casa)
  IF coalesce((p_dados->>'vertical')::boolean, false) THEN
    IF coalesce(p_dados->>'andares', '') ~ '^\s*\d+' THEN
      n := substring(p_dados->>'andares' from '\d+')::int;
      v_atual := substring(f.andares from '\d+')::int;
      IF n IS DISTINCT FROM v_atual THEN
        UPDATE condominio_ficha SET andares = n || ' andares' WHERE id = f.id;
        v_mudou := array_append(v_mudou, 'andares');
      END IF;
    END IF;
    IF coalesce(p_dados->>'elevadores', '') ~ '^\s*\d+' THEN
      n := substring(p_dados->>'elevadores' from '\d+')::int;
      v_atual := CASE WHEN coalesce(f.elevador, '') ~* '^\s*n[aã]o' THEN 0
                      ELSE coalesce(substring(f.elevador from '\d+')::int,
                                    CASE WHEN coalesce(btrim(f.elevador), '') <> '' THEN 1 END) END;
      IF n IS DISTINCT FROM v_atual THEN
        UPDATE condominio_ficha
           SET elevador = CASE n WHEN 0 THEN 'Não possui elevador' WHEN 1 THEN 'Sim, possui elevador'
                                 ELSE 'Sim, possui ' || n || ' elevadores' END
         WHERE id = f.id;
        v_mudou := array_append(v_mudou, 'elevadores');
      END IF;
    END IF;
  END IF;

  -- as características do condomínio: só ACRESCENTA o que a ficha ainda não tem
  IF jsonb_typeof(p_dados->'lazer') = 'array' THEN
    SELECT array_agg(s.x ORDER BY s.ord) INTO v_novos
      FROM (SELECT DISTINCT ON (lower(btrim(a.t))) btrim(a.t) AS x, a.ord
              FROM jsonb_array_elements_text(p_dados->'lazer') WITH ORDINALITY a(t, ord)
             WHERE btrim(a.t) <> ''
               AND NOT EXISTS (SELECT 1 FROM unnest(f.lazer) j WHERE lower(btrim(j)) = lower(btrim(a.t)))
             ORDER BY lower(btrim(a.t)), a.ord) s;
    IF coalesce(cardinality(v_novos), 0) > 0 THEN
      UPDATE condominio_ficha SET lazer = lazer || v_novos WHERE id = f.id;
      v_mudou := array_append(v_mudou, 'lazer');
    END IF;
  END IF;

  IF cardinality(v_mudou) > 0 THEN
    -- o endereço num texto só (é o que o CRM e a captação leem) acompanha os campos
    UPDATE condominio_ficha x
       SET atualizado_em = now(),
           endereco = CASE WHEN v_mudou && ARRAY['logradouro', 'numero', 'cidade', 'estado'] AND coalesce(x.logradouro, '') <> ''
                           THEN x.logradouro || coalesce(', nº ' || nullif(x.numero, ''), '')
                                || coalesce(', Bairro ' || nullif(coalesce(x.bairro, c.bairro), ''), '')
                                || coalesce(', ' || nullif(x.cidade, ''), '') || coalesce(' - ' || nullif(x.estado, ''), '')
                           ELSE x.endereco END
     WHERE x.id = f.id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'ficha_id', f.id, 'mudou', to_jsonb(v_mudou));
END;
$function$;

COMMENT ON FUNCTION public.site_condominio_guardar(integer, jsonb) IS
  '273: o cadastro de imóvel guarda no condomínio o que é do condomínio (endereço, número, CEP, andares, elevadores, características). Vazio não apaga; característica só acrescenta.';

REVOKE ALL ON FUNCTION public.site_condominio_guardar(integer, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_condominio_guardar(integer, jsonb) TO nay_site_escrita;

-- "andar não precisa": sai da régua do cadastro. Patch na função VIVA (o banco está à frente dos .sql).
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_imovel_pontos(integer)'::regprocedure);
  v_novo text;
BEGIN
  v_novo := regexp_replace(v_def, E'\\n[ \\t]*\\(''andar'',[^\\n]*', '');
  IF v_novo = v_def OR v_novo ~ E'\\(''andar''' THEN
    RAISE EXCEPTION '273: não achei (ou sobrou) a linha do andar em nai_imovel_pontos';
  END IF;
  EXECUTE v_novo;
END
$patch$;

COMMIT;
