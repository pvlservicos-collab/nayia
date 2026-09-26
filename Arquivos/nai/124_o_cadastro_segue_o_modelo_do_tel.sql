-- =====================================================================
-- NAI -- 124: o cadastro segue o modelo do Tel (26/09/2026)
--
-- Tel: "ela so precisa das informacoes e das fotos, ela deve pedir isso
-- para o cara, depois das informacoes ela deve checar um modelo para ver
-- se faltou algo e pedir", e mandou o modelo:
--
--     📍 Condominio Acquarelle
--     * Bairro: Ponta Negra
--     * Tamanho: 60m2
--     * Comodos: 2 quartos sendo 1 suite
--     * Banheiros: 2 banheiros
--     * Vagas de estacionamento: 1 vaga
--     * Mobilia: semi-mobiliado
--     Preco de Venda ou aluguel: R$ 450.000
--
-- O QUE ESTAVA QUEBRADO, medido na ficha 13 (Paradise River, 25/09):
-- condominio, bairro, quartos e valor preenchidos -- e `tipo` NULO. Como
-- `nai_imovel_novo_falta` perguntava o tipo PRIMEIRO, a Nay repetiu
-- "Me conta o que e: apartamento, casa ou outra coisa?" CINCO vezes
-- enquanto o corretor respondia tudo. Ele dizia "Paradise River, lá no Dom
-- Pedro", "3 dormitorios sendo uma suite", "3.650 + caucao e locacao" -- e
-- ela perguntava a mesma coisa de novo.
--
-- A causa: preencher a ficha dependia de o MODELO chamar
-- `nai_sec_guardar_do_imovel`. Ele chamava as vezes, e nunca com o tipo.
-- Instrucao em prompt nao e parede.
--
-- E quando o tipo vinha, vinha lixo: a ficha 4 foi SUBIDA para o catalogo
-- com tipo = "apartamentos, casas e imoveis em predios".
--
-- O CONSERTO, em tres partes:
--
-- 1. O BANCO LE A FICHA DO TEXTO. `nai_cadastro_ler` tira do que o corretor
--    escreveu tudo que der: area, quartos, suites, banheiros, vagas,
--    mobilia, valor, finalidade e tipo. Nao depende de ferramenta nenhuma.
--
-- 2. A ORDEM DAS PERGUNTAS E A DO MODELO DELE -- condominio, bairro,
--    tamanho, comodos, banheiros, vagas, mobilia, preco, fotos. O `tipo`
--    sai da fila de perguntas: ele se deduz do que o corretor falou, e o
--    modelo do Tel nem pede.
--
-- 3. UMA PERGUNTA SO POR VEZ, e nunca a mesma duas vezes se ele respondeu.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- O modelo do Tel tem banheiros; a ficha nao tinha onde guardar.
ALTER TABLE nai_imovel_novo ADD COLUMN IF NOT EXISTS banheiros integer;

-- ====================================================================
-- 1. O BANCO LE A FICHA DO TEXTO
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_cadastro_ler(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s text := lower(unaccent(coalesce(p_texto, '')));
  r jsonb := '{}'::jsonb;
  m text[];
BEGIN
  -- TAMANHO: "60m2", "60 m²", "60 metros"
  m := regexp_match(s, '(\d{2,4})\s*(m2|m²|mts?|metros)\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('area', (m[1])::numeric); END IF;

  -- COMODOS: "2 quartos", "3 dormitorios"
  m := regexp_match(s, '(\d{1,2})\s*(quartos?|dormit\w*|qtos?)\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('quartos', (m[1])::int); END IF;

  -- SUITES: "sendo 1 suite", "2 suites". "sendo uma suite" tambem.
  m := regexp_match(s, '(\d{1,2})\s*su[ií]tes?\M');
  IF m IS NOT NULL THEN
    r := r || jsonb_build_object('suites', (m[1])::int);
  ELSIF s ~ '\m(uma|1)\s+su[ií]te' THEN
    r := r || jsonb_build_object('suites', 1);
  END IF;

  -- BANHEIROS
  m := regexp_match(s, '(\d{1,2})\s*banheiros?\M');
  IF m IS NOT NULL THEN r := r || jsonb_build_object('banheiros', (m[1])::int); END IF;

  -- VAGAS
  m := regexp_match(s, '(\d{1,2})\s*vagas?\M');
  IF m IS NOT NULL THEN
    r := r || jsonb_build_object('vagas', (m[1])::int);
  ELSIF s ~ '\m(sem vaga|nao tem vaga)\M' THEN
    r := r || jsonb_build_object('vagas', 0);
  END IF;

  -- MOBILIA: a ordem importa, "semi" antes de "mobiliado"
  IF    s ~ '\msemi\s*-?\s*mobili'                      THEN r := r || '{"mobilia":"semi-mobiliado"}';
  ELSIF s ~ '\m(sem mobili|vazio|desmobili|nao mobili)' THEN r := r || '{"mobilia":"sem mobília"}';
  ELSIF s ~ '\mmobiliad'                                THEN r := r || '{"mobilia":"mobiliado"}';
  END IF;

  -- PRECO e FINALIDADE, das funcoes que ja existem e ja foram medidas
  IF nay_maior_valor(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('valor', nay_maior_valor(p_texto));
  END IF;
  IF nay_negocio_pedido(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('finalidade', nay_negocio_pedido(p_texto));
  END IF;

  -- TIPO: so o canonico, nunca a frase inteira. Foi assim que a ficha 4
  -- subiu com tipo = "apartamentos, casas e imoveis em predios".
  IF nai_tipo_canonico(p_texto) IS NOT NULL THEN
    r := r || jsonb_build_object('tipo', nai_tipo_canonico(p_texto));
  END IF;

  RETURN r;
END;
$function$;

-- ====================================================================
-- 2. ABSORVER: preenche o que falta, NUNCA sobrescreve o que ja tem
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_cadastro_absorver(p_id bigint, p_texto text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; n int := 0;
BEGIN
  IF p_id IS NULL OR coalesce(btrim(p_texto), '') = '' THEN RETURN 0; END IF;
  d := nai_cadastro_ler(p_texto);
  IF d = '{}'::jsonb THEN RETURN 0; END IF;

  UPDATE nai_imovel_novo n2 SET
    area       = coalesce(n2.area,       (d->>'area')::numeric),
    quartos    = coalesce(n2.quartos,    (d->>'quartos')::int),
    suites     = coalesce(n2.suites,     (d->>'suites')::int),
    banheiros  = coalesce(n2.banheiros,  (d->>'banheiros')::int),
    vagas      = coalesce(n2.vagas,      (d->>'vagas')::int),
    mobilia    = coalesce(n2.mobilia,    d->>'mobilia'),
    valor      = coalesce(n2.valor,      (d->>'valor')::numeric),
    finalidade = coalesce(n2.finalidade, d->>'finalidade'),
    tipo       = coalesce(n2.tipo,       d->>'tipo')
   WHERE n2.id = p_id AND n2.situacao = 'colhendo';

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;

-- ====================================================================
-- 3. O QUE FALTA, NA ORDEM DO MODELO DO TEL
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_imovel_novo_falta(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- A ordem e a do modelo que o Tel mandou em 26/09. `tipo` saiu da fila:
  -- ele se deduz do texto e o modelo dele nem pergunta.
  SELECT CASE
    WHEN coalesce(n.condominio, n.bairro) IS NULL THEN 'lugar'
    WHEN n.bairro     IS NULL THEN 'bairro'
    WHEN n.area       IS NULL THEN 'tamanho'
    WHEN n.quartos    IS NULL THEN 'comodos'
    WHEN n.banheiros  IS NULL THEN 'banheiros'
    WHEN n.vagas      IS NULL THEN 'vagas'
    WHEN n.mobilia    IS NULL THEN 'mobilia'
    WHEN n.valor      IS NULL OR n.finalidade IS NULL THEN 'preco'
    WHEN NOT EXISTS (SELECT 1 FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id) THEN 'fotos'
  END
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$;

CREATE OR REPLACE FUNCTION public.nai_imovel_novo_pergunta(p_falta text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_falta
    WHEN 'lugar'     THEN 'Qual o nome do condomínio ou do prédio?'
    WHEN 'bairro'    THEN 'Em que bairro ele fica?'
    WHEN 'tamanho'   THEN 'Qual o tamanho dele, em m²?'
    WHEN 'comodos'   THEN 'Quantos quartos? Algum deles é suíte?'
    WHEN 'banheiros' THEN 'Quantos banheiros?'
    WHEN 'vagas'     THEN 'Quantas vagas de garagem?'
    WHEN 'mobilia'   THEN 'É mobiliado, semi-mobiliado ou sem mobília?'
    WHEN 'preco'     THEN 'E o valor? É para venda ou para locação?'
    WHEN 'fotos'     THEN 'Agora me manda as fotos, por favor.'
  END;
$function$;

-- ====================================================================
-- 4. O MODELO, MONTADO DA FICHA -- e o que ela mostra no fim
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_cadastro_modelo(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT '📍 ' || coalesce(n.condominio, n.bairro, 'Imóvel')
    || E'\n* Bairro: '                  || coalesce(n.bairro, '?')
    || E'\n* Tamanho: '                 || coalesce(n.area::text || 'm2', '?')
    || E'\n* Cômodos: '                 || coalesce(n.quartos::text || ' quartos', '?')
         || coalesce(' sendo ' || n.suites::text || ' suíte', '')
    || E'\n* Banheiros: '               || coalesce(n.banheiros::text || ' banheiros', '?')
    || E'\n* Vagas de estacionamento: ' || coalesce(n.vagas::text || ' vaga', '?')
    || E'\n* Mobilia: '                 || coalesce(n.mobilia, '?')
    || E'\nPreço de '                   || coalesce(initcap(n.finalidade), 'Venda ou aluguel')
         || ': ' || coalesce('R$ ' || to_char(n.valor, 'FM999G999G999D00'), '?')
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$;

COMMIT;

\echo '=== o que ela tira do texto do corretor ==='
SELECT jsonb_pretty(nai_cadastro_ler(
  'Taí, Nay. Paradise River, no Dom Pedro. 3 dormitórios sendo uma suíte, 2 banheiros, 1 vaga, 60m2, semi-mobiliado. 3.650 + caução, é locação'));

\echo '=== e a ficha 13, que estava travada ==='
SELECT nai_cadastro_absorver(13,
  'Paradise River, no Dom Pedro. 3 dormitórios sendo uma suíte, 2 banheiros, 1 vaga, 60m2, semi-mobiliado. 3.650 é locação') AS absorveu;
SELECT nai_imovel_novo_falta(13) AS ainda_falta,
       nai_imovel_novo_pergunta(nai_imovel_novo_falta(13)) AS ela_pergunta;
SELECT nai_cadastro_modelo(13) AS modelo;

-- =====================================================================
-- COMO DESFAZER: reaplicar as duas funcoes da 99 (falta e pergunta). A
-- coluna `banheiros` e as funcoes novas ficam sem uso e nao atrapalham.
-- =====================================================================
