-- 222 (30/09/2026): A FRANCISCA (…6604) E AS LISTAS.
-- Pedro: "depois de agradecer pelo carinho a mulher mandou um áudio perguntando
-- sobre imóveis e ela mandou já opções sem fazer o filtro ... deveria ter
-- perguntado a faixa de preço e depois os bairros; e na hora de mandar a lista
-- precisa ser uma lista mais bonitinha: nome do imóvel, endereço, informações,
-- preços, mobiliado sim ou não, quantidade de quartos, condomínio, todas as
-- mobílias que tem ... e um imóvel semimobiliado ela deve dizer 'Esse imóvel está
-- 80% mobiliado, serve para seu cliente?'".
--
-- O que aconteceu (áudio: "tu tem um apartamento que seja mobiliado? ... então tem
-- algum..."):
--   1. nai_pede_os_valores achou "TEM ALGUM" = "ele pediu os valores" -> a busca
--      pulou a pergunta do valor (a regra 100 é para "quais os valores que você
--      tem", "me manda todas as opções"). Sai "tem/teria algum(a)/algo".
--   2. A conta "o bairro tem pouca coisa" rodava SEM bairro (a cidade inteira) e
--      também pulava o valor. Agora só com bairro dado.
--   3. A lista da busca termina com "Qual deles é de seu interesse?", e a parede
--      da ficha (14i) trocava a LISTA inteira por "Qual deles?" + fichas curtas --
--      a lista bonita nunca chegava. A ficha não mexe mais em lista da busca.
--   4. A LISTA NOVA (nai_bloco_oferta): nome, endereço, quartos/banheiros/vagas/
--      área, preço com o que o aluguel inclui (condomínio, água, gás, IPTU),
--      mobília ("sim", ou "semimobiliado: está 80% mobiliado") com os itens que o
--      anúncio cita, e o lazer do condomínio. O card de um imóvel só (o dos grupos)
--      não muda; o semimobiliado ganha "Esse imóvel está 80% mobiliado, serve para
--      seu cliente?".
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1 ------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.nai_pede_os_valores(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 222: saiu "(tem|teria) (alguma|algum|algo)" e "ja tem algum": "tem algum
  -- apartamento mobiliado?" é pedido NOVO e passa pelo filtro, não "me mostra tudo"
  SELECT s ~ ('(quais? (sao )?(os )?(valor|preco)|'
           || '(valor|preco)e?s? que (voce|vc|tu) tem|'
           || 'quanto (ta|esta|e) (o )?(aluguel|valor)|'
           || 'o que (voce|vc|tu) tem|'
           || 'que que (voce|vc) tem|'
           || 'todas as opcoes|todas opcoes|todos os (imoveis|que tiver)|'
           || 'me (manda|passa|mostra) (tudo|todas|todos|a lista|as opcoes)|'
           || 'quais (voce|vc) tem|quais tem\M)')
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 2 ------------------------------------------------------------------------
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$                   OR nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                      BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5);$a$,
$b$                   -- 222: "o bairro tem pouca coisa" só com bairro dado (sem bairro,
                   -- a conta era da cidade inteira e pulava a pergunta do valor)
                   OR (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND NOT nai_e_a_cidade(p_bairro)
                       AND nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                           BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5));$b$);

-- 2b: PEDIDO NOVO COMEÇA PELO VALOR. O caminho "veio do grupo" (região primeiro)
-- valia sempre que a conversa JÁ tinha imóvel -- a Francisca, que já tinha recebido
-- opções, pediu outro ("tem algum mobiliado?") e ouviu "em qual bairro?". Pedro: "ela
-- deveria ter perguntado a faixa de preço e depois os bairros". Agora é "do grupo" só
-- quando ESTA mensagem cita um imóvel (código, card colado ou nome de condomínio).
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL;$a$,
$b$  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL
              OR NOT (cardinality(nay_codigos_citados(coalesce(t.texto, ''))) > 0
                      OR coalesce(t.texto, '') ~* 'c[oó]digo:'
                      OR coalesce(array_length(nai_imovel_pelo_condominio(coalesce(t.texto, ''), ''), 1), 0) > 0);$b$);

-- 3 ------------------------------------------------------------------------
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$  IF v_corretor AND position('📍' IN v_texto) = 0 AND v_texto ~ '\?' THEN$a$,
$b$  -- 222: a LISTA da busca (blocos "*Nome #1234*") não vira ficha: ela termina com
  -- "Qual deles é de seu interesse?" e a parede trocava a lista inteira por fichas
  IF v_corretor AND position('📍' IN v_texto) = 0 AND v_texto ~ '\?'
     AND v_texto !~ ' #[0-9]{3,5}\*'
     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))) THEN$b$);

-- 4 ------------------------------------------------------------------------
-- a mobília em uma linha: "sim", ou semimobiliado com os 80%, e os itens que o anúncio cita
CREATE OR REPLACE FUNCTION nai_mobilia_da_lista(p_codigo integer)
 RETURNS text LANGUAGE sql STABLE AS $$
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
  SELECT CASE
    WHEN lower(coalesce(i.mobilia, '')) ~ '^semi' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ 'semi.?mobiliad')
      THEN 'Semimobiliado: está 80% mobiliado' || coalesce(' (' || itens.lista || ')', '')
    WHEN lower(coalesce(i.mobilia, '')) ~ '^mobiliad' OR (coalesce(i.mobilia, '') = '' AND i.tudo ~ '\mmobiliad')
      THEN 'Mobiliado: sim' || coalesce(' (' || itens.lista || ')', '')
    WHEN lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN 'Mobiliado: não, só com ar-condicionado'
    ELSE NULL END
    FROM i, itens;
$$;

CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer, p_negocio text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
-- 222 (Pedro, 30/09): "uma lista mais bonitinha: nome do imóvel, endereço,
-- informações, preços, mobiliado sim ou não, quartos, condomínio ... quanto mais
-- informações melhor, mas sem encher muito texto". A primeira linha continua
-- "*Nome #1234*": é por ela que a busca e as paredes reconhecem um bloco.
DECLARE
  i imoveis; v_tit text; v_ico text; v_l text[] := '{}'; v_end text; v_inc text[]; v_inclui text;
  v_medidas text[] := '{}'; v_mob text; v_lazer text;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  v_ico := CASE WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN '🏠' ELSE '🏢' END;
  v_tit := coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''), initcap(coalesce(nullif(i.tipo, ''), 'Imóvel')));

  -- 📍 endereço · bairro
  v_end := concat_ws(', ', nullif(btrim(i.logradouro), ''), nullif(btrim(i.numero), ''));
  v_end := concat_ws(' · ', nullif(v_end, ''), nullif(btrim(i.bairro), ''));

  -- quartos · banheiros · vagas · área
  IF coalesce(i.quartos, 0) > 0 THEN
    v_medidas := v_medidas || (i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END
                 || CASE WHEN coalesce(i.suites, 0) > 0 THEN ' (' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte)' ELSE ' suítes)' END ELSE '' END);
  END IF;
  IF coalesce(i.banheiros, 0) > 0 THEN v_medidas := v_medidas || (i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END); END IF;
  IF coalesce(i.vagas, 0) > 0 THEN v_medidas := v_medidas || (i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga' ELSE ' vagas' END); END IF;
  IF coalesce(i.area_util, 0) > 0 THEN v_medidas := v_medidas || (trim(to_char(i.area_util, 'FM999990')) || ' m²'); END IF;
  IF array_length(v_medidas, 1) > 0 THEN v_l := v_l || ('• ' || array_to_string(v_medidas, ' · ')); END IF;

  -- o preço, com o que o aluguel inclui
  SELECT array_agg(n ORDER BY o) INTO v_inc FROM (VALUES
      (1, 'condomínio', 'condom'), (2, 'água', 'agua'), (3, 'gás', '\mgas'), (4, 'IPTU', 'iptu'), (5, 'energia', 'energia|luz')) x(o, n, rx)
   WHERE lower(unaccent(coalesce(i.extras->>'incluso no aluguel', ''))) ~ x.rx;
  v_inclui := CASE WHEN array_length(v_inc, 1) > 0 THEN ' (inclui ' || nai_lista_pt(v_inc) || ')'
                   WHEN coalesce(i.taxa_condominio, 0) > 0
                     THEN ' + condomínio R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.')
                   ELSE '' END;
  IF coalesce(p_negocio, 'ambos') IN ('locacao', 'ambos') AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_l := v_l || ('• Aluguel R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') || '/mês' || v_inclui);
  END IF;
  -- VENDA NAO LEVA "/mes" (Tel, 22/09)
  IF coalesce(p_negocio, 'ambos') IN ('venda', 'ambos') AND coalesce(i.valor_venda, 0) > 0 THEN
    v_l := v_l || ('• Venda R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.')
                   || CASE WHEN lower(coalesce(i.extras->>'aceita financiamento', '')) ~ '^s' THEN ' (aceita financiamento)' ELSE '' END);
  END IF;

  v_mob := nai_mobilia_da_lista(i.codigo);
  IF v_mob IS NOT NULL THEN v_l := v_l || ('• ' || v_mob); END IF;

  -- o lazer do condomínio que o anúncio antigo cita (até 4, sem "condomínio fechado")
  SELECT string_agg(x, ', ') INTO v_lazer FROM (
    SELECT DISTINCT ON (lower(x)) x FROM imovel_ficha f, unnest(f.caracteristicas_condominio) x
     WHERE f.codigo = i.codigo AND x !~* 'condom[ií]nio fechado|[aá]gua de po[cç]o|g[aá]s encanado'
     LIMIT 4) z;
  IF v_lazer IS NOT NULL THEN v_l := v_l || ('• Condomínio: ' || lower(v_lazer)); END IF;

  RETURN v_ico || ' *' || v_tit || ' #' || i.codigo || '*'
         || CASE WHEN nullif(v_end, '') IS NOT NULL THEN E'\n📍 ' || v_end ELSE '' END
         || CASE WHEN array_length(v_l, 1) > 0 THEN E'\n' || array_to_string(v_l, E'\n') ELSE '' END;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer)
 RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nai_bloco_oferta(p_codigo, 'ambos');
$$;

-- o semimobiliado na lista e no card de um imóvel só
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';$a$,
$b$  -- 222: sem outra pergunta (a parede de uma pergunta por mensagem cortaria)
  IF coalesce(v_aqui, '') || coalesce(v_alt, '') ~ 'está 80% mobiliado' THEN
    v_txt := v_txt || E'\n\n' || 'Os semimobiliados estão 80% mobiliados.';
  END IF;
  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';$b$);

SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$       || (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc)),$a$,
$b$       || (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc)
       -- 222: o semimobiliado pergunta se serve
       || CASE WHEN coalesce(v_aqui, '') || coalesce(v_alt, '') ~ 'está 80% mobiliado'
               THEN E'\n\n' || 'Esse imóvel está 80% mobiliado, serve para seu cliente?' ELSE '' END),$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'Minha colega, tu tem um apartamento que seja mobiliado? Então tem algum', 'pede_lista', 'false',
   '"tem algum" é pedido novo: passa pelo filtro (valor e bairro)');
COMMIT;
