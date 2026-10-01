-- 248 (01/10/2026): CADASTRO PENDENTE -- O QUE PRECISA DE GENTE, NUMA ABA SÓ.
-- Pedro: "cria a ferramenta completa de cadastro de imóveis importando tudo
-- direitinho, e lá em imóveis cria uma aba CADASTRO PENDENTE e põe lá esses
-- para cadastro por humano".
--
-- Hoje o que precisa de gente está espalhado e invisível: 50 imóveis em
-- Rascunho, 1 bloqueado (o 5747, o único que a secretária criou), 4 no ar sem
-- foto nenhuma, 24 no ar faltando campo ESSENCIAL, 1 com a foto num link
-- temporário da Z-API (morre e nem passa na conferência do envio) e 13 fichas
-- de imóvel NOVO que o dono ditou na captação e ninguém cadastrou.
--
--   nai_cadastro_pendente()     a lista, com o motivo de cada um, a pontuação
--                               (244) e o que falta. Sem telefone: dado de
--                               pessoa não sai em lista.
--   nai_cadastro_importar(cod)  "importando tudo direitinho": puxa a ficha da
--                               conversa para os campos VAZIOS, liga o
--                               condomínio pelo nome e traz o endereço dele,
--                               acerta o proprietário nos dois lados e devolve
--                               o antes/depois da pontuação.
--   nai_foto_trocar_url(...)    troca a URL de uma foto (o site baixa a foto de
--                               fora para o nosso servidor e chama isto).
--
-- NADA aqui publica imóvel: a situação continua sendo escolha de gente, no
-- editor. O que a ferramenta faz é não deixar ninguém digitar o que já sabemos.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_cadastro_pendente()
 RETURNS TABLE(fonte text, codigo integer, ficha_id bigint, titulo text, tipo text, bairro text,
               condominio text, origem text, status text, pct integer, falta text[], motivos text[],
               fotos integer, fotos_de_fora integer, dono text, atualizado timestamptz, dados jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH f AS (   -- as fotos: quantas, e quantas estão num link que não é nosso
    SELECT codigo, count(*)::int AS n,
           count(*) FILTER (WHERE url !~ '^https://imobeasy\.(com|online)/')::int AS de_fora
      FROM imovel_fotos GROUP BY codigo
  ),
  fichas AS (   -- a ficha da conversa que ninguém aplicou
    SELECT c.id, c.lead_id, c.tipo, c.codigo, c.dados, c.estado, c.atualizado_em,
           nullif(btrim(l.nome), '') AS dono
      FROM captacao_cadastro c
      LEFT JOIN captacao_leads l ON l.id = c.lead_id
     WHERE c.estado IN ('coletando', 'pronto')
  ),
  im AS (
    SELECT i.codigo, i.status, i.origem, i.tipo, i.bairro,
           nullif(btrim(i.condominio_nome), '') AS condominio,
           coalesce(f.n, 0) AS fotos, coalesce(f.de_fora, 0) AS de_fora,
           p.pct, p.falta, p.falta_essencial, p.oferecido,
           i.bloqueado, i.criado_em,
           (SELECT pr.nome FROM proprietarios pr WHERE pr.id = i.proprietario_id) AS dono,
           (SELECT max(x.id) FROM fichas x WHERE x.codigo = i.codigo) AS ficha_id,
           array_remove(ARRAY[
             CASE WHEN i.status = 'Rascunho' THEN 'pré-cadastro (Rascunho)' END,
             CASE WHEN i.bloqueado THEN 'bloqueado: a Nay não oferece' END,
             CASE WHEN p.oferecido AND coalesce(f.n, 0) = 0 THEN 'no ar sem nenhuma foto' END,
             CASE WHEN p.oferecido AND p.falta_essencial <> '{}' THEN 'falta o essencial: ' || array_to_string(p.falta_essencial, ', ') END,
             CASE WHEN coalesce(f.de_fora, 0) > 0 THEN 'foto em link de fora (' || f.de_fora || '): some quando expirar' END,
             CASE WHEN EXISTS (SELECT 1 FROM fichas x WHERE x.codigo = i.codigo) THEN 'o dono ditou dados na conversa e ninguém aplicou' END
           ], NULL) AS motivos
      FROM imoveis i
      LEFT JOIN f ON f.codigo = i.codigo
      LEFT JOIN vw_imovel_pontuacao p ON p.codigo = i.codigo
  )
  SELECT 'imovel'::text, im.codigo, im.ficha_id,
         coalesce(im.condominio, im.tipo, 'Imóvel ' || im.codigo),
         im.tipo, im.bairro, im.condominio, im.origem, im.status,
         im.pct, im.falta, im.motivos, im.fotos, im.de_fora, im.dono, im.criado_em, NULL::jsonb
    FROM im WHERE im.motivos <> '{}'
  UNION ALL
  -- a ficha de imóvel NOVO: o dono contou tudo e o imóvel nem existe ainda
  SELECT 'ficha'::text, NULL::integer, x.id,
         coalesce(nullif(btrim(x.dados->>'condominio'), ''), nullif(btrim(x.dados->>'tipo'), ''), 'Imóvel novo'),
         nullif(btrim(x.dados->>'tipo'), ''), nullif(btrim(x.dados->>'bairro'), ''),
         nullif(btrim(x.dados->>'condominio'), ''), 'captacao', 'Sem cadastro',
         NULL::integer, '{}'::text[],
         ARRAY['o dono ditou o imóvel na conversa e ele não está cadastrado'],
         0, 0, x.dono, x.atualizado_em, x.dados
    FROM fichas x WHERE x.codigo IS NULL AND x.tipo <> 'atualizar'
$function$;
COMMENT ON FUNCTION nai_cadastro_pendente() IS '248: o que precisa de gente para terminar o cadastro, com o motivo de cada um';
REVOKE ALL ON FUNCTION nai_cadastro_pendente() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_cadastro_pendente() TO nay_site_leitura;
GRANT EXECUTE ON FUNCTION nai_cadastro_pendente() TO nay_site_escrita;

-- "IMPORTANDO TUDO DIREITINHO": o que já sabemos entra sem ninguém digitar.
-- Só campo VAZIO é preenchido (nunca sobrescreve o que uma pessoa escreveu) e
-- a situação do imóvel não é tocada.
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
COMMENT ON FUNCTION nai_cadastro_importar(integer) IS '248: puxa para o imóvel tudo o que já sabemos (ficha da conversa, condomínio, endereço, proprietário), só em campo vazio';
REVOKE ALL ON FUNCTION nai_cadastro_importar(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_cadastro_importar(integer) TO nay_site_escrita;

-- A FOTO QUE MORA FORA: o site baixa e chama isto para apontar para a nossa.
CREATE OR REPLACE FUNCTION public.nai_foto_trocar_url(p_codigo integer, p_de text, p_para text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE v_n int;
BEGIN
  IF p_para !~ '^https://imobeasy\.online/fotos/[0-9]+/' THEN
    RAISE EXCEPTION 'a URL nova tem que ser do nosso servidor: %', p_para;
  END IF;
  UPDATE imovel_fotos SET url = p_para WHERE codigo = p_codigo AND url = p_de;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $function$;
REVOKE ALL ON FUNCTION nai_foto_trocar_url(integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION nai_foto_trocar_url(integer, text, text) TO nay_site_escrita;
COMMIT;
