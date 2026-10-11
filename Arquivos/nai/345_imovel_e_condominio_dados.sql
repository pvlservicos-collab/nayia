-- 345 -- Os DADOS da reforma (Pedro, 11/10/2026): mobília em 4 níveis, observação do imóvel, área por tipo, as
--        características do condomínio saem do imóvel e vão para a ficha do condomínio, imóvel ligado ao condomínio
--
-- Antes de tudo a 344 (colunas) e o backup completo local (Arquivos/backups-locais/naydb-completo-2026-10-11_1802).
-- Cada mudança aqui tem o valor de antes em privado.imovel_antes_345 / privado.condominio_ficha_antes_345.
-- Nenhuma linha de imoveis é apagada (regra da casa).
--
-- 1. MOBÍLIA: "pelado, ou seja, sem nada; climatizado, só; com modulados e ar, que é o antigo semimobiliado; e
--    mobiliado". O valor gravado passa a ser um dos quatro rótulos de nay_mobilia_rotulo. Onde o campo estava
--    vazio e a característica dizia (Mobiliado / Semi-Mobiliado / só Climatizado), o campo é preenchido.
-- 2. OBSERVAÇÃO: "muitos imóveis já têm essa descrição... já pega essas informações e coloca nesse campo": o bloco
--    OBS do anúncio (imovel_ficha.observacoes); na falta, a descrição curta (até 400 caracteres).
-- 3. ÁREA POR TIPO: em casa, "o que hoje chama de área total" é o tamanho do terreno (vai para extras.tamanho do
--    terreno, como o site antigo escreve) e area_total fica vazia; apartamento segue com útil e total.
-- 4. CONDOMÍNIO: o imóvel que só tinha o NOME do condomínio é ligado pelo id (um nome, um condomínio); as
--    características de condomínio (dos anúncios e das listas dos imóveis) vão para a ficha do condomínio em
--    lazer / segurança / comodidades, e SAEM da lista do imóvel vertical (apartamento, flat, cobertura, sala);
--    numa casa de condomínio saem só as que são do condomínio mesmo (portaria, salão, quadra...): piscina e
--    churrasqueira podem ser da casa. Elevador e a taxa por quartos entram na ficha quando os imóveis dizem.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ---- 0. o retrato de antes --------------------------------------------------------------------------------
INSERT INTO privado.imovel_antes_345 (codigo, mobilia, area_total, caracteristicas, extras_condominio, condo_id, observacao)
SELECT codigo, mobilia, area_total, caracteristicas, extras -> 'caracteristicas do condominio', condo_id, observacao
  FROM imoveis ON CONFLICT (codigo) DO NOTHING;
INSERT INTO privado.condominio_ficha_antes_345 SELECT * FROM condominio_ficha
 WHERE NOT EXISTS (SELECT 1 FROM privado.condominio_ficha_antes_345 a WHERE a.id = condominio_ficha.id);

-- ---- 1. mobília -------------------------------------------------------------------------------------------
UPDATE imoveis SET mobilia = nay_mobilia_rotulo(nay_mobilia_nivel(mobilia))
 WHERE nay_mobilia_nivel(mobilia) IS NOT NULL AND mobilia IS DISTINCT FROM nay_mobilia_rotulo(nay_mobilia_nivel(mobilia));
UPDATE imoveis SET mobilia = CASE
         WHEN EXISTS (SELECT 1 FROM unnest(caracteristicas) c WHERE lower(unaccent(c)) ~ '^semi.?mobiliad') THEN 'com modulados e ar'
         WHEN EXISTS (SELECT 1 FROM unnest(caracteristicas) c WHERE lower(unaccent(c)) ~ '^mobiliad') THEN 'mobiliado'
         WHEN EXISTS (SELECT 1 FROM unnest(caracteristicas) c WHERE lower(unaccent(c)) ~ '^(climatizad|ar.condicionado)') THEN 'só climatizado' END
 WHERE coalesce(btrim(mobilia), '') = '' AND cardinality(coalesce(caracteristicas, '{}')) > 0
   AND EXISTS (SELECT 1 FROM unnest(caracteristicas) c WHERE lower(unaccent(c)) ~ '^(semi.?mobiliad|mobiliad|climatizad|ar.condicionado)');

-- ---- 2. observação ----------------------------------------------------------------------------------------
UPDATE imoveis i SET observacao = left(btrim(f.observacoes), 1000)
  FROM imovel_ficha f
 WHERE f.codigo = i.codigo AND f.encontrado AND coalesce(btrim(f.observacoes), '') <> '' AND coalesce(btrim(i.observacao), '') = '';
UPDATE imoveis SET observacao = btrim(descricao)
 WHERE coalesce(btrim(observacao), '') = '' AND coalesce(btrim(descricao), '') <> '' AND length(btrim(descricao)) <= 400;

-- ---- 3. área por tipo (casa) ------------------------------------------------------------------------------
UPDATE imoveis SET extras = coalesce(extras, '{}'::jsonb)
                  || jsonb_build_object('tamanho do terreno', trim(to_char(area_total, 'FM999999990.##')) || ' m2')
 WHERE tipo IN ('Casa', 'Casa de condomínio', 'Chácara/Sítio/Fazenda Residencial', 'Chácara/Sítio/Fazenda Comercial')
   AND coalesce(area_total, 0) > 0 AND coalesce(extras ->> 'tamanho do terreno', '') = '';
UPDATE imoveis SET area_total = NULL
 WHERE tipo IN ('Casa', 'Casa de condomínio', 'Chácara/Sítio/Fazenda Residencial', 'Chácara/Sítio/Fazenda Comercial')
   AND area_total IS NOT NULL AND coalesce(extras ->> 'tamanho do terreno', '') <> '';

-- ---- 4a. o imóvel ligado ao condomínio pelo id (um nome, um condomínio) -----------------------------------
WITH nomes AS (
  SELECT lower(unaccent(btrim(nome))) AS n, min(id) AS id, count(*) AS q FROM condominios GROUP BY 1 HAVING count(*) = 1)
UPDATE imoveis i SET condo_id = nomes.id
  FROM nomes
 WHERE i.condo_id IS NULL AND coalesce(btrim(i.condominio_nome), '') <> ''
   AND lower(unaccent(btrim(i.condominio_nome))) = nomes.n
   AND i.condominio_nome !~* '(nao|não) identificad|^(casa|apartamento|predio|prédio|livre|sala|loja|lote|flat)s?$';

-- ---- 4b. as características do condomínio, classificadas ----------------------------------------------------
CREATE TEMP TABLE _classe (nome text PRIMARY KEY, grupo text NOT NULL, da_casa boolean NOT NULL DEFAULT false);
INSERT INTO _classe VALUES
 ('academia','lazer',false),('bicicletario','lazer',false),('brinquedoteca','lazer',false),('car wash box','lazer',false),
 ('churrasqueira','lazer',true),('ciclovia','lazer',false),('cinema','lazer',false),('espaco zen','lazer',false),
 ('espaco gourmet','lazer',true),('fitness','lazer',false),('forno de pizza','lazer',false),('hidromassagem','lazer',true),
 ('jardim','lazer',true),('lan house','lazer',false),('lounge','lazer',false),('pergolado','lazer',false),('pet place','lazer',false),
 ('piscina','lazer',true),('pista de caminhada','lazer',false),('pista de cooper','lazer',false),('pista de skate','lazer',false),
 ('playground','lazer',false),('prainha','lazer',false),('quadra de areia','lazer',false),('quadra de volei','lazer',false),
 ('quadra de squash','lazer',false),('quadra de tenis','lazer',false),('quadra poliesportiva','lazer',false),('redario','lazer',false),
 ('salao de festas','lazer',false),('salao de jogos','lazer',false),('sauna','lazer',true),('solarium','lazer',true),('solario','lazer',true),
 ('spa','lazer',true),('area de lazer','lazer',false),('quadra','lazer',false),
 ('condominio fechado','seguranca',false),('guarita 24 horas','seguranca',false),('guarita','seguranca',false),('portaria','seguranca',false),
 ('seguranca 24 horas','seguranca',false),('seguranca 24h','seguranca',false),('porteiro','seguranca',false),('portao eletronico','seguranca',false),
 ('cerca eletrica','seguranca',true),('camera de seguranca','seguranca',true),('sistema de camera','seguranca',true),('interfone','seguranca',true),
 ('elevador','comodidades',false),('lavanderia','comodidades',false),('gerador de energia','comodidades',false),
 ('gerador de energia - 100%','comodidades',false),('gas encanado','comodidades',false),('agua de poco','comodidades',false),
 ('poco','comodidades',true),('recepcao','comodidades',false);
CREATE FUNCTION pg_temp.chave(t text) RETURNS text LANGUAGE sql IMMUTABLE AS
  $$ SELECT btrim(regexp_replace(lower(unaccent(coalesce(t, ''))), '\s+', ' ', 'g')) $$;
CREATE FUNCTION pg_temp.vertical(t text) RETURNS boolean LANGUAGE sql IMMUTABLE AS
  $$ SELECT coalesce(t, '') ~* '^(apartamento|flat|cobertura|sala|loja|studio|kitnet|loft)' $$;

-- de onde cada característica de condomínio vem: o anúncio (todas as do bloco do condomínio) e a lista do
-- imóvel (as classificadas; numa casa de condomínio só as que não podem ser da casa)
CREATE TEMP TABLE _vinda AS
  SELECT i.condo_id, x AS nome, coalesce(k.grupo, 'lazer') AS grupo
    FROM imoveis i JOIN imovel_ficha f ON f.codigo = i.codigo AND f.encontrado
    CROSS JOIN unnest(f.caracteristicas_condominio) x
    LEFT JOIN _classe k ON k.nome = pg_temp.chave(x)
   WHERE i.condo_id IS NOT NULL AND btrim(x) <> ''
  UNION ALL
  SELECT i.condo_id, x, k.grupo
    FROM imoveis i CROSS JOIN unnest(i.caracteristicas) x
    JOIN _classe k ON k.nome = pg_temp.chave(x)
   WHERE i.condo_id IS NOT NULL AND (pg_temp.vertical(i.tipo) OR (i.tipo ~* 'condom' AND NOT k.da_casa));

-- a ficha de quem ainda não tem (nome repetido ganha o id entre parênteses, como o salvar faz)
INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
SELECT c.id, c.nome, c.bairro, 'características dos anúncios e dos imóveis (345)'
  FROM condominios c
 WHERE c.id IN (SELECT DISTINCT condo_id FROM _vinda)
   AND NOT EXISTS (SELECT 1 FROM condominio_ficha f WHERE f.condominio_id = c.id)
   AND NOT EXISTS (SELECT 1 FROM condominio_ficha f WHERE lower(f.nome) = lower(c.nome));
INSERT INTO condominio_ficha (condominio_id, nome, bairro, fonte)
SELECT c.id, c.nome || ' (' || c.id || ')', c.bairro, 'características dos anúncios e dos imóveis (345)'
  FROM condominios c
 WHERE c.id IN (SELECT DISTINCT condo_id FROM _vinda)
   AND NOT EXISTS (SELECT 1 FROM condominio_ficha f WHERE f.condominio_id = c.id);

-- junta ao que a ficha já tinha, sem repetir (a redação que já estava vence)
CREATE FUNCTION pg_temp.juntar(a text[], b text[]) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(array_agg(x ORDER BY o), '{}')
    FROM (SELECT DISTINCT ON (pg_temp.chave(x)) x, o
            FROM unnest(coalesce(a, '{}') || coalesce(b, '{}')) WITH ORDINALITY u(x, o)
           WHERE btrim(x) <> '' ORDER BY pg_temp.chave(x), o) s $$;
UPDATE condominio_ficha f
   SET lazer       = pg_temp.juntar(f.lazer,       (SELECT array_agg(DISTINCT v.nome) FROM _vinda v WHERE v.condo_id = f.condominio_id AND v.grupo = 'lazer')),
       seguranca   = pg_temp.juntar(f.seguranca,   (SELECT array_agg(DISTINCT v.nome) FROM _vinda v WHERE v.condo_id = f.condominio_id AND v.grupo = 'seguranca')),
       comodidades = pg_temp.juntar(f.comodidades, (SELECT array_agg(DISTINCT v.nome) FROM _vinda v WHERE v.condo_id = f.condominio_id AND v.grupo = 'comodidades')),
       atualizado_em = now()
 WHERE f.condominio_id IN (SELECT DISTINCT condo_id FROM _vinda);

-- o que é do condomínio SAI da lista do imóvel (o que a tela "O que tem" separava em dois grupos)
UPDATE imoveis i
   SET caracteristicas = (SELECT coalesce(array_agg(x ORDER BY o), '{}')
                            FROM unnest(i.caracteristicas) WITH ORDINALITY u(x, o)
                            LEFT JOIN _classe k ON k.nome = pg_temp.chave(x)
                           WHERE k.nome IS NULL OR (NOT pg_temp.vertical(i.tipo) AND NOT (i.tipo ~* 'condom' AND NOT k.da_casa))),
       extras = coalesce(i.extras, '{}'::jsonb) - 'caracteristicas do condominio'
 WHERE i.condo_id IS NOT NULL AND cardinality(coalesce(i.caracteristicas, '{}')) > 0
   AND EXISTS (SELECT 1 FROM unnest(i.caracteristicas) x JOIN _classe k ON k.nome = pg_temp.chave(x)
                WHERE pg_temp.vertical(i.tipo) OR (i.tipo ~* 'condom' AND NOT k.da_casa));
UPDATE imoveis SET extras = extras - 'caracteristicas do condominio' WHERE extras ? 'caracteristicas do condominio';

-- ---- 4c. elevador e taxa por quartos, pelo que os imóveis dizem ------------------------------------------
UPDATE condominio_ficha f SET elevador = 'Sim, possui elevador'
 WHERE coalesce(btrim(f.elevador), '') = '' AND EXISTS (SELECT 1 FROM unnest(f.comodidades) c WHERE pg_temp.chave(c) = 'elevador');
UPDATE condominio_ficha f SET elevador = 'Não possui elevador'
 WHERE coalesce(btrim(f.elevador), '') = ''
   AND NOT EXISTS (SELECT 1 FROM unnest(f.comodidades) c WHERE pg_temp.chave(c) = 'elevador')
   AND cardinality(f.lazer || f.seguranca || f.comodidades) > 0          -- a ficha conhece o condomínio
   AND EXISTS (SELECT 1 FROM imoveis i WHERE i.condo_id = f.condominio_id
                AND coalesce(i.extras ->> 'lances de escada', '') ~ '^\s*[1-9]');
UPDATE condominio_ficha f
   SET taxas = (SELECT jsonb_agg(jsonb_build_object('quartos', q, 'condominio', v, 'fonte', 'imóveis') ORDER BY q)
                  FROM (SELECT i.quartos AS q, mode() WITHIN GROUP (ORDER BY i.taxa_condominio) AS v
                          FROM imoveis i
                         WHERE i.condo_id = f.condominio_id AND pg_temp.vertical(i.tipo)
                           AND coalesce(i.taxa_condominio, 0) > 0 AND coalesce(i.quartos, 0) > 0
                         GROUP BY i.quartos) s)
 WHERE f.taxas = '[]'::jsonb
   AND EXISTS (SELECT 1 FROM imoveis i WHERE i.condo_id = f.condominio_id AND pg_temp.vertical(i.tipo)
                AND coalesce(i.taxa_condominio, 0) > 0 AND coalesce(i.quartos, 0) > 0);

-- ---- 5. as funções da Nay velha que leem a mobília, e o card com a observação -------------------------
-- (parte da 345, na MESMA transação dos dados) As funções da Nay velha que liam a mobília pela redação antiga
-- ("^semi", "mobiliad", "ar.condicionado") passam a ler pelo nível (nay_mobilia_nivel), que entende as duas
-- redações; o card ganha a observação do imóvel. Cada remendo exige o trecho exato UMA vez na função viva.
CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;

-- o card do banco: a linha da mobília pelo nível, e a observação logo abaixo (Pedro, 11/10: "vai o card com
-- essas informações e o texto da observação junto")
SELECT pg_temp.remendar('nai_card_do_banco(integer)',
$de$      || CASE WHEN lower(coalesce(b.mobilia, '')) ~ '^semi' THEN E'
• semi-mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ '^mobiliad' THEN E'
• mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ 'ar.condicionado' THEN E'
• climatizado' ELSE '' END$de$,
$para$      || CASE nay_mobilia_nivel(b.mobilia) WHEN 'semi' THEN E'
• com modulados e ar'
              WHEN 'mobiliado' THEN E'
• mobiliado'
              WHEN 'climatizado' THEN E'
• só climatizado'
              WHEN 'nada' THEN E'
• sem mobília' ELSE '' END
      -- 345: a observação do imóvel ("falta só TV", "vista para o rio", "o dono aceita outro imóvel")
      || CASE WHEN coalesce(btrim(b.observacao), '') <> '' THEN E'
• ' || left(regexp_replace(btrim(b.observacao), '\s*\n+\s*', ' / ', 'g'), 300) ELSE '' END$para$);

-- a resposta da base ("é mobiliado?")
SELECT pg_temp.remendar('nai_resposta_da_base(integer,text)',
$de$    IF lower(coalesce(i.mobilia, '')) ~ '^semi' THEN
      r := r || 'é semi-mobiliado'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;$de$,
$para$    IF nay_mobilia_nivel(i.mobilia) = 'semi' THEN
      r := r || 'é com modulados e ar'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'mobiliado' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'climatizado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;
    ELSIF nay_mobilia_nivel(i.mobilia) = 'nada' THEN
      r := r || 'não é mobiliado'::text || 'está sem nada'::text;$para$);

-- a busca por perfil (com / sem mobília)
SELECT pg_temp.remendar('nai_oferta_serve(imoveis,text,numeric,integer,boolean,boolean,text,text)',
$de$     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR coalesce(i.mobilia, '') ~* 'mobiliad')$de$,
$para$     AND (NOT p_sem OR (coalesce(nay_mobilia_nivel(i.mobilia), '') NOT IN ('semi', 'mobiliado') AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR nay_mobilia_nivel(i.mobilia) IN ('semi', 'mobiliado'))$para$);
SELECT pg_temp.remendar('nay_buscar_por_perfil(text,text,text,text,text)',
$de$       AND (NOT v_quer_sem OR (
             coalesce(i.mobilia,'') !~* 'mobiliad'
             AND coalesce(i.descricao,'') !~* '\mmobiliad'))
       AND (NOT v_quer_com OR (
             coalesce(i.mobilia,'') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
             OR coalesce(i.descricao,'') ~* '(mobiliad|modulad|planejad)'))$de$,
$para$       AND (NOT v_quer_sem OR (
             coalesce(nay_mobilia_nivel(i.mobilia), '') NOT IN ('semi', 'mobiliado')
             AND coalesce(i.descricao,'') !~* '\mmobiliad'))
       AND (NOT v_quer_com OR (
             nay_mobilia_nivel(i.mobilia) IN ('semi', 'mobiliado', 'climatizado')
             OR coalesce(i.descricao,'') ~* '(mobiliad|modulad|planejad)'))$para$);
-- a tela Enviar imóvel
SELECT pg_temp.remendar('nai_disparo_buscar(text,numeric,numeric,text[],text[],text[],integer[],integer)',
$de$          OR ('mobiliado' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'mobiliad%')
          OR ('semi' = ANY (f.mobs) AND lower(unaccent(coalesce(i.mobilia, ''))) LIKE 'semi%'))$de$,
$para$          OR ('mobiliado' = ANY (f.mobs) AND nay_mobilia_nivel(i.mobilia) = 'mobiliado')
          OR ('semi' = ANY (f.mobs) AND nay_mobilia_nivel(i.mobilia) = 'semi'))$para$);
-- o cadastro lido de texto (equipe manda imóvel) grava os rótulos novos
SELECT pg_temp.remendar('nai_cadastro_ler(text)',
$de$  IF    s ~ '\msemi\s*-?\s*mobili'                      THEN r := r || '{"mobilia":"semi-mobiliado"}';
  ELSIF s ~ '\m(sem mobili|vazio|desmobili|nao mobili)' THEN r := r || '{"mobilia":"sem mobília"}';
  ELSIF s ~ '\mmobiliad'                                THEN r := r || '{"mobilia":"mobiliado"}';$de$,
$para$  IF    s ~ '\m(semi\s*-?\s*mobili|modulad)'            THEN r := r || '{"mobilia":"com modulados e ar"}';
  ELSIF s ~ '\m(sem mobili|vazio|desmobili|nao mobili)' THEN r := r || '{"mobilia":"sem nada"}';
  ELSIF s ~ '\mmobiliad'                                THEN r := r || '{"mobilia":"mobiliado"}';
  ELSIF s ~ '\m(so|somente) (climatizad|ar)'            THEN r := r || '{"mobilia":"só climatizado"}';$para$);

-- a frase da mobília no bloco de oferta
CREATE OR REPLACE FUNCTION public.nai_mobilia_da_lista(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH i AS (SELECT im.*, lower(unaccent(concat_ws(' ', im.mobilia, array_to_string(im.caracteristicas, ' '), im.descricao,
                         (SELECT f.descricao FROM imovel_ficha f WHERE f.codigo = im.codigo)))) AS tudo
               FROM imoveis im WHERE im.codigo = p_codigo),
  itens AS (SELECT string_agg(x.nome, ', ' ORDER BY x.o) AS lista
              FROM i, (VALUES (1, 'geladeira', 'geladeira'), (2, 'fogão', 'fogao|cooktop'), (3, 'micro-ondas', 'micro.?ondas'),
                              (4, 'máquina de lavar', 'maquina de lavar|lava.?roupa'), (5, 'cama', '\mcama'),
                              (6, 'guarda-roupa', 'guarda.?roupa|roupeiro'), (7, 'armários planejados', 'planejad'),
                              (8, 'sofá', '\msofa'), (9, 'mesa', '\mmesa'), (10, 'TV', '\mtv\M|televis'),
                              (11, 'ar-condicionado', 'ar.?condicionado|\mar\M|climatizad')) AS x(o, nome, rx)
             WHERE i.tudo ~ x.rx)
  -- 345: pelo nível (nay_mobilia_nivel lê a redação antiga e a nova)
  SELECT CASE
    WHEN nay_mobilia_nivel(i.mobilia) = 'semi' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ 'semi.?mobiliad')
      THEN 'Com modulados e ar (o antigo semimobiliado): está 80% mobiliado' || coalesce(' (' || itens.lista || ')', '')
    WHEN nay_mobilia_nivel(i.mobilia) = 'mobiliado' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ '\mmobiliad')
      THEN 'Mobiliado: sim' || coalesce(' (' || itens.lista || ')', '')
    WHEN nay_mobilia_nivel(i.mobilia) = 'climatizado' THEN 'Mobiliado: não, só climatizado (ar-condicionado)'
    WHEN nay_mobilia_nivel(i.mobilia) = 'nada' THEN 'Mobiliado: não, está sem nada'
    ELSE NULL END
    FROM i, itens;
$function$;

COMMIT;
