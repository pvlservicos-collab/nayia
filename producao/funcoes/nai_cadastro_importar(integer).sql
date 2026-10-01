CREATE OR REPLACE FUNCTION public.nai_cadastro_importar(p_codigo integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  i          imoveis;
  i0         jsonb;      -- o imóvel ANTES, para dizer só o que mudou de verdade
  ficha      record;
  d          jsonb := '{}'::jsonb;
  v_antes    int;
  v_depois   int;
  entraram   text[] := '{}';
  v_condo    record;
  v_negocio  text;
  v_vende    boolean;
  v_aluga    boolean;
  v_dono     int;
  v_n        int;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo FOR UPDATE;
  IF i.codigo IS NULL THEN RETURN jsonb_build_object('erro', 'imóvel não encontrado'); END IF;
  i0      := to_jsonb(i);
  v_antes := (nai_imovel_pontos(p_codigo)->>'pct')::int;

  -- 1. A FICHA DA CONVERSA (a do próprio imóvel, ou a de imóvel novo que já
  --    aponta para ele por `extras.captacao_ficha`)
  SELECT c.* INTO ficha
    FROM captacao_cadastro c
   WHERE c.estado IN ('coletando', 'pronto')
     AND (c.codigo = p_codigo OR c.id::text = i.extras->>'captacao_ficha')
   ORDER BY (c.estado = 'pronto') DESC, c.atualizado_em DESC
   LIMIT 1;
  IF ficha.id IS NOT NULL THEN d := coalesce(ficha.dados, '{}'::jsonb); END IF;

  v_negocio := lower(coalesce(d->>'negocio', ''));
  v_vende   := v_negocio ~ 'vend|amb';
  v_aluga   := NOT (v_negocio ~ 'vend' AND v_negocio !~ 'amb');

  UPDATE imoveis SET
    tipo            = coalesce(nullif(btrim(tipo), ''), nullif(btrim(initcap(d->>'tipo')), '')),
    bairro          = coalesce(nullif(btrim(bairro), ''), nullif(btrim(d->>'bairro'), '')),
    condominio_nome = coalesce(nullif(btrim(condominio_nome), ''), nullif(btrim(d->>'condominio'), '')),
    quartos         = coalesce(quartos,   captacao_numero(d->>'quartos')::int),
    suites          = coalesce(suites,    captacao_numero(d->>'suites')::int),
    banheiros       = coalesce(banheiros, captacao_numero(d->>'banheiros')::int),
    vagas           = coalesce(vagas,     captacao_numero(d->>'vagas')::int),
    area_util       = coalesce(area_util, captacao_numero(d->>'area')),
    taxa_condominio = coalesce(taxa_condominio, captacao_numero(d->>'condominio_valor')),
    iptu            = coalesce(iptu,      captacao_numero(d->>'iptu')),
    mobilia         = coalesce(nullif(btrim(mobilia), ''), nullif(btrim(d->>'mobilia'), '')),
    descricao       = coalesce(nullif(btrim(descricao), ''),
                               CASE WHEN coalesce(btrim(d->>'detalhes'), '') <> ''
                                    THEN 'O dono contou na captação: ' || btrim(d->>'detalhes') END),
    valor_aluguel   = coalesce(valor_aluguel, CASE WHEN v_aluga THEN captacao_numero(d->>'valor') END),
    valor_venda     = coalesce(valor_venda,   CASE WHEN v_vende THEN captacao_numero(d->>'valor') END),
    extras          = CASE WHEN coalesce(btrim(d->>'incluso'), '') <> '' AND NOT coalesce(extras, '{}'::jsonb) ? 'incluso no aluguel'
                           THEN coalesce(extras, '{}'::jsonb) || jsonb_build_object('incluso no aluguel', btrim(d->>'incluso'))
                           ELSE extras END
   WHERE codigo = p_codigo;

  -- 2. O CONDOMÍNIO pelo nome, e o endereço dele (da ficha do condomínio ou da
  --    moda dos imóveis já ligados -- nunca inventado)
  SELECT i2.* INTO i FROM imoveis i2 WHERE i2.codigo = p_codigo;
  IF i.condo_id IS NULL AND coalesce(btrim(i.condominio_nome), '') <> '' THEN
    SELECT c.id, c.nome INTO v_condo
      FROM condominios c
     WHERE nay_sem_acento(lower(btrim(c.nome))) = nay_sem_acento(lower(btrim(i.condominio_nome)))
     LIMIT 1;
    IF v_condo.id IS NOT NULL THEN
      UPDATE imoveis SET condo_id = v_condo.id WHERE codigo = p_codigo;
      i.condo_id := v_condo.id;
    END IF;
  END IF;
  IF i.condo_id IS NOT NULL THEN
    WITH m AS (
      SELECT mode() WITHIN GROUP (ORDER BY x.logradouro) FILTER (WHERE coalesce(x.logradouro, '') <> '') AS logradouro,
             mode() WITHIN GROUP (ORDER BY x.cidade)     FILTER (WHERE coalesce(x.cidade, '') <> '')     AS cidade,
             mode() WITHIN GROUP (ORDER BY x.estado)     FILTER (WHERE coalesce(x.estado, '') <> '')     AS estado,
             mode() WITHIN GROUP (ORDER BY x.bairro)     FILTER (WHERE coalesce(x.bairro, '') <> '')     AS bairro
        FROM imoveis x WHERE x.condo_id = i.condo_id AND x.codigo <> p_codigo
    )
    UPDATE imoveis t SET
      logradouro = coalesce(nullif(btrim(t.logradouro), ''),
                            (SELECT nullif(btrim(cf.endereco), '') FROM condominio_ficha cf WHERE cf.condominio_id = i.condo_id LIMIT 1),
                            m.logradouro),
      bairro     = coalesce(nullif(btrim(t.bairro), ''), m.bairro),
      cidade     = coalesce(nullif(btrim(t.cidade), ''), m.cidade, 'Manaus'),
      estado     = coalesce(nullif(btrim(t.estado), ''), m.estado, 'AM')
      FROM m WHERE t.codigo = p_codigo;
  END IF;

  -- 3. O PROPRIETÁRIO nos dois lados (a Nay lê o imovel_privado, 162)
  SELECT proprietario_id INTO v_dono FROM imovel_privado WHERE codigo = p_codigo;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.proprietario_id IS NULL AND v_dono IS NOT NULL THEN
    UPDATE imoveis SET proprietario_id = v_dono WHERE codigo = p_codigo;
  ELSIF i.proprietario_id IS NOT NULL AND v_dono IS NULL THEN
    INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (p_codigo, i.proprietario_id)
      ON CONFLICT (codigo) DO UPDATE SET proprietario_id = EXCLUDED.proprietario_id;
    entraram := array_append(entraram, 'proprietário no lado privado (é por lá que a Nay acha o dono)');
  END IF;

  -- 4. a ficha fica como aplicada, para não voltar na lista
  IF ficha.id IS NOT NULL THEN
    UPDATE captacao_cadastro SET estado = 'aplicado', codigo = p_codigo, aplicado_em = now(),
           aplicado_por = 'cadastro pendente', atualizado_em = now()
     WHERE id = ficha.id;
  END IF;

  -- O QUE ENTROU é o diff das colunas, não o que a função tentou: dizer
  -- "puxei a ficha" quando o campo já estava preenchido seria mentira na tela.
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  entraram := entraram || coalesce((
    SELECT array_agg(CASE a.key
             WHEN 'condo_id' THEN 'condomínio ligado ao cadastro'
             WHEN 'condominio_nome' THEN 'nome do condomínio'
             WHEN 'logradouro' THEN 'rua' WHEN 'area_util' THEN 'área'
             WHEN 'taxa_condominio' THEN 'taxa de condomínio'
             WHEN 'valor_aluguel' THEN 'valor do aluguel' WHEN 'valor_venda' THEN 'valor de venda'
             WHEN 'proprietario_id' THEN 'proprietário' WHEN 'extras' THEN 'incluso no aluguel'
             WHEN 'descricao' THEN 'descrição' WHEN 'mobilia' THEN 'mobília'
             WHEN 'suites' THEN 'suítes' ELSE a.key END ORDER BY a.key)
      FROM jsonb_each_text(i0) a
      JOIN jsonb_each_text(to_jsonb(i)) b ON b.key = a.key
     WHERE coalesce(a.value, '') <> coalesce(b.value, '')), '{}'::text[]);

  v_depois := (nai_imovel_pontos(p_codigo)->>'pct')::int;
  SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = p_codigo;
  RETURN jsonb_build_object('codigo', p_codigo, 'entraram', to_jsonb(entraram),
                            'pct_antes', v_antes, 'pct_depois', v_depois,
                            'fotos', v_n, 'pontuacao', nai_imovel_pontos(p_codigo));
END $function$;
