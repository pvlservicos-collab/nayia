-- =====================================================================
-- NAI -- 98: venda nao e aluguel, e casa nao e apartamento
-- (Tel, 22/09/2026)
--
-- Ele: "o cliente pediu imoveis de venda e ela enviou locacao, isso precisa
-- estar bem dividido, qualquer valor acima de 100k ele ta falando de vendas".
-- E logo depois: "o cara disse busco CASA, ela tem que saber interpretar se o
-- cara quer casa ou apartamento e responder corretamente".
-- E ainda: "o fluxo de vendas e igual locacao, tem visita, manda imovel, so
-- muda que e vendas".
--
-- POR QUE ACONTECEU (nao foi o modelo inventando):
--   1. `nai_buscar_por_perfil` era de LOCACAO por construcao -- filtrava e
--      ordenava por `valor_aluguel`, dizia "outras opcoes de locacao" e
--      chamava a busca antiga com 'locacao' escrito fixo. Pedido de venda
--      entrava ali e so podia sair aluguel.
--   2. `nai_oferta_serve` exigia `valor_aluguel > 0`: imovel de venda era
--      descartado antes de ser olhado. Medido: dos 288 imoveis no mercado,
--      246 tem valor de venda e so 39 tem aluguel -- ela enxergava um canto
--      do catalogo.
--   3. `nay_negocio_pedido` so olhava palavra (venda/comprar/aluguel).
--      "ate 700 mil" nao dizia nada, e a conversa seguia como locacao.
--   4. A busca NAO TINHA filtro de tipo. "Busco casa" e "quero apartamento"
--      davam exatamente a mesma lista.
--
-- O LEITOR DE VALOR: `nay_valor_em_reais` pega o PRIMEIRO numero da frase --
-- em "3 quartos ate 700 mil" ele le 3. Por isso entra `nay_maior_valor`, que
-- pega o MAIOR e que ignora telefone, CEP, data e hora: sem isso um numero de
-- WhatsApp viraria um imovel de 92 bilhoes e toda conversa seria "venda".
--
-- O QUE NAO MUDA: o fluxo. Mesma sequencia de perguntas, mesmo card, mesma
-- visita. So a finalidade e o tipo passam a ser respeitados.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------------- O MAIOR VALOR DA FRASE
CREATE OR REPLACE FUNCTION public.nay_maior_valor(p_texto text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  s text := lower(unaccent(coalesce(p_texto, '')));
  m text[];
  v numeric;
  v_max numeric := NULL;
BEGIN
  -- FORA DA CONTA primeiro: telefone, CEP, data, hora, CPF/CNPJ. Sao numeros
  -- grandes que nao sao preco -- e um deles sozinho jogaria a conversa toda
  -- para "venda".
  s := regexp_replace(s, '\(?\d{2}\)?\s*9?\d{4}[-. ]?\d{4}', ' ', 'g');  -- telefone
  s := regexp_replace(s, '\d{5}-?\d{3}\M', ' ', 'g');                     -- CEP
  s := regexp_replace(s, '\d{1,2}/\d{1,2}(/\d{2,4})?', ' ', 'g');         -- data
  s := regexp_replace(s, '\d{1,2}:\d{2}', ' ', 'g');                      -- hora
  s := regexp_replace(s, '\d{3}\.\d{3}\.\d{3}-\d{2}', ' ', 'g');          -- CPF
  s := regexp_replace(s, '\d{10,}', ' ', 'g');                            -- numerao solto

  -- "700 mil", "700k", "1,5 mil"
  FOR m IN SELECT regexp_matches(s, '(\d{1,4}(?:[.,]\d{1,3})?)\s*(mil|k)\M', 'g') LOOP
    v := replace(m[1], ',', '.')::numeric * 1000;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  -- "1 milhao", "1.2 mi"
  FOR m IN SELECT regexp_matches(s, '(\d{1,3}(?:[.,]\d{1,2})?)\s*(milhao|milhoes|mi)\M', 'g') LOOP
    v := replace(m[1], ',', '.')::numeric * 1000000;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  -- "750.000", "R$ 2.600", "R$ 700000"
  FOR m IN SELECT regexp_matches(s, '(\d{1,3}(?:\.\d{3})+)(?:,\d{2})?', 'g') LOOP
    v := replace(m[1], '.', '')::numeric;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;
  FOR m IN SELECT regexp_matches(s, 'r\$\s*(\d{4,9})', 'g') LOOP
    v := m[1]::numeric;
    IF v_max IS NULL OR v > v_max THEN v_max := v; END IF;
  END LOOP;

  RETURN v_max;
END;
$function$;

-- 2 --------------------------------------- VENDA PELA PALAVRA OU PELO VALOR
CREATE OR REPLACE FUNCTION public.nay_negocio_pedido(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text := lower(unaccent(coalesce(p_texto,'')));
  v boolean := t ~ '\m(venda|vender|vendas|comprar|compra|a venda|vendo)\M';
  l boolean := t ~ '\m(locacao|aluguel|alugar|aluga|alugado|locar)\M';
  v_valor numeric;
BEGIN
  IF v AND l THEN RETURN 'ambos'; END IF;
  IF v THEN RETURN 'venda'; END IF;
  IF l THEN RETURN 'locacao'; END IF;

  -- ACIMA DE 100 MIL E VENDA (Tel, 22/09). Aluguel em Manaus nao chega perto
  -- disso; quem fala de 700 mil esta falando de compra, mesmo sem dizer a
  -- palavra. O piso fica em `nai_config` para ele mexer sem deploy.
  v_valor := nay_maior_valor(t);
  IF v_valor IS NOT NULL AND v_valor >= nai_cfg_int('piso_venda', 100000) THEN
    RETURN 'venda';
  END IF;
  RETURN NULL;
END;
$function$;

INSERT INTO nai_config (chave, valor)
     VALUES ('piso_venda', '100000')
ON CONFLICT (chave) DO NOTHING;

-- 3 ------------------------------------------------ O TIPO, NA PALAVRA DELE
CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Devolve o padrao que casa com `imoveis.tipo`. A ordem e a mesma de
  -- `nai_imovel_pela_descricao`: "casa" antes de "condominio", senao "casa de
  -- condominio" cai no lugar errado. 'Casa%' pega as 25 casas e as 83 casas de
  -- condominio; 'Apartamento%' pega os 134 e o "em Via Publica".
  SELECT CASE
    WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
    WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
    WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
    WHEN s ~ '\m(sala|salas|andar)\M'                       THEN 'Sala%'
    WHEN s ~ '\m(loja|lojas|ponto)\M'                       THEN 'Loja%'
    WHEN s ~ '\m(galpao|galpoes|deposito)\M'                THEN 'Galp%'
    WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
    WHEN s ~ '\m(predio|predios)\M'                         THEN 'Pr%dio%'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

CREATE OR REPLACE FUNCTION public.nai_rotulo_do_tipo(p_tipo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_tipo
    WHEN 'Casa%'        THEN 'casa'      WHEN 'Apartamento%' THEN 'apartamento'
    WHEN 'Cobertura%'   THEN 'cobertura' WHEN 'Flat%'        THEN 'flat'
    WHEN 'Sala%'        THEN 'sala'      WHEN 'Loja%'        THEN 'ponto'
    WHEN 'Galp%'        THEN 'galpão'    WHEN 'Lote%'        THEN 'terreno'
    WHEN 'Ch%'          THEN 'chácara'   WHEN 'Pr%dio%'      THEN 'prédio'
  END;
$function$;

-- 4 ------------------------------------------ O QUE ELE PEDIU NA CONVERSA
-- A sequencia de perguntas gasta tres mensagens: quando a busca finalmente
-- roda, o texto do turno e so "700 mil" ou "Aleixo". O que ele disse no
-- comeco -- "busco casa para comprar" -- esta nos turnos de tras.
CREATE OR REPLACE FUNCTION public.nai_negocio_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    nay_negocio_pedido(coalesce(p_texto, '')),
    (SELECT nay_negocio_pedido(t.texto) FROM nai_turno t
      WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '24 hours'
        AND nay_negocio_pedido(t.texto) IS NOT NULL
      ORDER BY t.id DESC LIMIT 1));
$function$;

CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    nai_tipo_pedido(coalesce(p_texto, '')),
    (SELECT nai_tipo_pedido(t.texto) FROM nai_turno t
      WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '24 hours'
        AND nai_tipo_pedido(t.texto) IS NOT NULL
      ORDER BY t.id DESC LIMIT 1));
$function$;

-- 5 ------------------------------------------- O CRIVO, AGORA COM FINALIDADE
-- A versao de 6 parametros fica como esta (locacao, sem tipo): quem chama ela
-- -- `nai_imovel_pela_descricao` -- identifica imovel, nao oferta.
CREATE OR REPLACE FUNCTION public.nai_oferta_serve(i imoveis, p_telefone text, p_teto numeric,
                                                   p_quartos integer, p_sem boolean, p_com boolean,
                                                   p_negocio text, p_tipo text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND (p_tipo IS NULL OR i.tipo ILIKE p_tipo)
     -- A FINALIDADE manda no preco que vale. 'venda' olha valor_venda,
     -- 'locacao' olha valor_aluguel, e sem saber vale qualquer um dos dois --
     -- o card mostra os dois preços de qualquer jeito.
     AND CASE coalesce(p_negocio, 'ambos')
           WHEN 'venda'   THEN coalesce(i.valor_venda, 0) > 0
                           AND (p_teto IS NULL OR i.valor_venda BETWEEN
                                  p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                              AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
           WHEN 'locacao' THEN coalesce(i.valor_aluguel, 0) > 0
                           AND (p_teto IS NULL OR i.valor_aluguel BETWEEN
                                  p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                              AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
           ELSE (coalesce(i.valor_aluguel, 0) > 0
                 AND (p_teto IS NULL OR i.valor_aluguel BETWEEN
                        p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                    AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)))
             OR (coalesce(i.valor_venda, 0) > 0
                 AND (p_teto IS NULL OR i.valor_venda BETWEEN
                        p_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 15) / 100.0)
                    AND p_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0)))
         END
     AND (p_quartos IS NULL OR p_quartos = 0 OR i.quartos = p_quartos)
     AND (NOT p_sem OR (coalesce(i.mobilia, '') !~* 'mobiliad' AND coalesce(i.descricao, '') !~* '\mmobiliad'))
     AND (NOT p_com OR (coalesce(i.mobilia, '') ~* '(mobiliad|modulad|planejad|ar-condicionado)'
                        OR coalesce(i.descricao, '') ~* '(mobiliad|modulad|planejad)'))
     AND NOT EXISTS (SELECT 1 FROM envios e
                      WHERE e.codigo = i.codigo::text AND e.enviado_em > now() - interval '30 days'
                        AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8));
$function$;

-- 6 ------------------------------------------ O BLOCO COM O PRECO QUE IMPORTA
CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer, p_negocio text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE i imoveis; v_tit text; v_ico text; v_mob text; v_l text[] := '{}';
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  v_ico := CASE WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN '🏠' ELSE '🏢' END;
  v_tit := CASE
    WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
      THEN nai_condominio_ok(i.condominio_nome) || coalesce(' — ' || nullif(i.bairro, ''), '')
    ELSE initcap(coalesce(nullif(i.tipo, ''), 'Imóvel')) || coalesce(' no bairro ' || nullif(i.bairro, ''), '') END;
  IF coalesce(i.quartos, 0) > 0 THEN
    v_l := v_l || ('• ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
                   CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END);
  END IF;
  -- VENDA NAO LEVA "/mes" (Tel, 22/09). Numa lista de venda sai so o preco de
  -- venda; numa de locacao, so o aluguel; sem saber, sai o que o imovel tiver.
  IF coalesce(p_negocio, 'ambos') IN ('venda', 'ambos') AND coalesce(i.valor_venda, 0) > 0 THEN
    v_l := v_l || ('• R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.'));
  END IF;
  IF coalesce(p_negocio, 'ambos') IN ('locacao', 'ambos') AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_l := v_l || ('• R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') || '/mês');
  END IF;
  v_mob := CASE
    WHEN lower(coalesce(i.mobilia, '')) ~ '^semi' THEN 'Semimobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN 'Mobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN 'Com ar-condicionado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'semi.?mobiliad' THEN 'Semimobiliado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'mobiliad' THEN 'Mobiliado' END;
  IF v_mob IS NOT NULL THEN v_l := v_l || ('• ' || v_mob); END IF;
  RETURN v_ico || ' *' || v_tit || ' #' || i.codigo || '*' ||
         CASE WHEN array_length(v_l, 1) > 0 THEN E'\n' || array_to_string(v_l, E'\n') ELSE '' END;
END;
$function$;

COMMIT;

-- Como a peneira le o que ele escreveu.
SELECT nay_maior_valor(t) AS maior_valor, nay_negocio_pedido(t) AS negocio,
       nai_tipo_pedido(t) AS tipo, t AS frase
  FROM unnest(ARRAY[
    'tenho cliente para 3 quartos ate 700 mil no aleixo',
    'busco CASA no parque 10',
    'Esse edificio saint honoré 750 mil tá valendo?',
    'o cliente paga até 3.500 de aluguel',
    'quero alugar uma casa de 2 quartos',
    'tem apartamento no Aleixo de 2 quartos?',
    'meu cliente tem 1.2 milhão para investir',
    'fala com o 92 99602-6529',
    'CEP 69050-000, visita dia 23/09 as 15:00'
  ]) t;
