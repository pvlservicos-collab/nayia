-- 225 (30/09/2026): OS FILTROS ACEITAM O QUE ELE JÁ DISSE; A FAIXA DE VALOR É FIRME.
-- Pedro, sobre a Maria Soraia: "ela perguntou de novo se é mobiliado sendo que a
-- Maria já disse mobiliado; preciso de flexibilidade na hora de aceitar os
-- filtros ... deixa de forma que ela preencha os filtros caso já tenha as
-- informações nas conversas anteriores, e só peça o que faltar"; "use palavras
-- semelhantes em todos os parâmetros de filtros, condomínios, bairros, tudo";
-- "o filtro financeiro ela errou: o filtro é 20% a menos ou 10% a mais e o cara
-- queria coisa de 4 mil, e ela mandou de 2.500"; "coloca nos filtros para ela
-- perguntar se é venda ou locação antes de mandar o card ou imóvel também".
--
-- O que aconteceu (30/09, 13h27-14h07): "Mobiliado R$4,000 ... Adrianópolis,
-- Vieiralves ... 1 quarto ou 2" -> "E eles têm preferência por semimobiliado ou
-- mobiliado?" (a regra 13 escolhia a pergunta da sequência sem olhar o que já
-- estava dito). "Até 4 mil" na Ponta Negra -> lista de R$ 2.600, 2.500 e 1.900
-- (o atalho da 218: faixa vazia mostrava o que coubesse no valor).
--
--   faixa firme         -20% / +10% (faixa_abaixo_pct, faixa_acima_pct). Faixa
--                       vazia: diz a faixa e oferece ver mais em conta ou outro
--                       bairro; os mais em conta só saem se ele PEDIR
--                       (nai_pede_mais_em_conta: "pode ser mais barato").
--   só o que falta      a pergunta da sequência (regra 13) pula o que o perfil
--                       do cliente já tem (bairro, valor, mobília); tudo sabido,
--                       o texto do modelo passa como veio.
--   palavras parecidas  mobília: mobilhado/mobilado/com móveis/equipado; sem:
--                       vazio/desocupado/sem móveis. quartos por extenso ("dois
--                       quartos"). tipo: apt/apê/apart./kitnet/studio/loft.
--                       negócio: financiamento/comprador -> venda; inquilino/
--                       locatário/alugue/alugou -> locação. bairro parecido
--                       (>= 0,6) entra sem perguntar; 0,45-0,6 confirma.
--   alugar ou comprar   imóvel que serve aos dois (20 no mercado) e conversa
--   antes do card       sem negócio: "O seu cliente quer alugar ou comprar?"
--                       antes do card, uma vez em 24 h. Imóvel de uma
--                       finalidade só: o card já diz.
BEGIN;
SET LOCAL lock_timeout = '3s';

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

-- 1 ---------------------------------------------- ELE PEDIU MAIS EM CONTA
CREATE OR REPLACE FUNCTION public.nai_pede_mais_em_conta(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 225: só aqui a busca sai da faixa de -20%/+10% para baixo
  SELECT x ~ '\m(mais em conta|mais barat\w*|mais acessive\w*|abaixo (disso|desse valor|do valor)|menos que isso|menor valor|qualquer valor|pode ser (mais|menor|abaixo)|nao tem problema o valor|o valor nao importa|independente do valor)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$function$;

UPDATE nai_config SET valor = '20', atualizado_em = now() WHERE chave = 'faixa_abaixo_pct' AND valor <> '20';

-- a faixa vazia NÃO mostra os mais em conta sozinha (era o atalho da 218)
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  IF v_aqui IS NULL AND v_alt IS NULL AND v_teto IS NOT NULL THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_aqui FROM ($a$,
$b$  -- 225: SÓ SE ELE PEDIR ("pode ser mais em conta"). Pedro, 30/09: "o filtro é
  -- 20% a menos ou 10% a mais; o cara queria coisa de 4 mil e ela mandou de 2.500".
  IF v_aqui IS NULL AND v_alt IS NULL AND v_teto IS NOT NULL AND nai_pede_mais_em_conta(t.texto) THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v DESC) INTO v_aqui FROM ($b$);

-- o "não" diz a faixa e oferece o caminho
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$       || CASE WHEN v_teto IS NULL AND NOT v_sem_valor
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               ELSE '' END)::text,$a$,
$b$       || CASE WHEN v_teto IS NULL AND NOT v_sem_valor
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               -- 225: a faixa é firme; mais em conta só se ele pedir
               WHEN v_teto IS NOT NULL
               THEN ' Eu procurei entre R$ ' || nai_valor_curto(v_teto * (1 - nai_cfg_int('faixa_abaixo_pct', 20) / 100.0))
                    || ' e R$ ' || nai_valor_curto(v_teto * (1 + nai_cfg_int('faixa_acima_pct', 10) / 100.0))
                    || '. Se o cliente aceitar algo mais em conta ou outro bairro, me fala que eu vejo aqui.'
               ELSE '' END)::text,$b$);

CREATE OR REPLACE FUNCTION public.nai_valor_curto(p numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 3200 -> "3.200"; 3520.5 -> "3.520"; 450000 -> "450.000"
  SELECT replace(to_char(round(coalesce(p, 0)), 'FM999G999G999'), ',', '.');
$function$;

-- 2 ------------------------------------ A PERGUNTA DA SEQUÊNCIA SÓ DO QUE FALTA
CREATE OR REPLACE FUNCTION public.nai_uma_pergunta_da_sequencia(p_texto text, p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text := coalesce(p_texto, ''); p_bai int; p_pre int; p_mob int;
  pf nai_perfil_cliente;
  sabe_bairro boolean := false; sabe_valor boolean := false; sabe_mob boolean := false;
BEGIN
  IF t !~ '\?' OR t ~* 'c[óo]digo:' OR length(t) >= 300 THEN RETURN NULL; END IF;
  p_bai := coalesce(nullif(strpos(lower(t), 'bairro'), 0), 0);
  p_pre := coalesce(nullif(strpos(lower(t), 'faixa de pre'), 0), 0);
  p_mob := coalesce(nullif(strpos(lower(t), 'mobiliad'), 0), 0);
  IF (CASE WHEN p_bai > 0 THEN 1 ELSE 0 END) + (CASE WHEN p_pre > 0 THEN 1 ELSE 0 END)
   + (CASE WHEN p_mob > 0 THEN 1 ELSE 0 END) < 2 THEN RETURN NULL; END IF;

  -- 225: O QUE ELE JÁ DISSE NÃO SE PERGUNTA (Pedro, 30/09: a Maria Soraia disse
  -- "Mobiliado R$4,000 ... Adrianópolis" e ouviu "prefere semimobiliado ou
  -- mobiliado?"). O perfil do cliente (223) guarda o que a busca já recebeu.
  IF p_contato IS NOT NULL THEN
    SELECT * INTO pf FROM nai_perfil_ativo(p_contato);
    sabe_bairro := nullif(btrim(coalesce(pf.bairros, '')), '') IS NOT NULL;
    sabe_valor  := pf.teto IS NOT NULL;
    sabe_mob    := nullif(btrim(coalesce(pf.mobilia, '')), '') IS NOT NULL;
  END IF;

  RETURN CASE
    WHEN p_bai > 0 AND NOT sabe_bairro
      THEN 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'
    WHEN p_pre > 0 AND NOT sabe_valor
      THEN 'E qual a faixa de preço que seus clientes estão buscando?'
    WHEN p_mob > 0 AND NOT sabe_mob
      THEN 'E eles têm preferência por semimobiliado ou mobiliado?'
    ELSE NULL END;
END;
$function$;

SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$    v_novo := nai_uma_pergunta_da_sequencia(v_texto);$a$,
$b$    v_novo := nai_uma_pergunta_da_sequencia(v_texto, t.contato_id);  -- 225: só o que falta$b$);

-- 3 ------------------------------------------ PALAVRAS PARECIDAS NOS FILTROS
-- mobília
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';$a$,
$b$  -- 225: palavras parecidas ("mobilhado", "com móveis", "equipado"; "vazio", "desocupado")
  v_sem := v_mob ~ '\m(sem|nao|vazio|vazia|desocupad\w*|desmobiliad\w*|nada de movei\w*)' AND v_mob !~ '\msemi';
  v_com := NOT v_sem AND v_mob ~ '(\m(com|mobili\w*|mobilh\w*|mobilad\w*|semi\w*|modulad\w*|planejad\w*|equipad\w*|montad\w*)|movei\w*|movel\M)';$b$);

-- quartos por extenso
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$  SELECT min(x[1]::int), max(x[1]::int) INTO v_q_min, v_q_max
    FROM regexp_matches(coalesce(p_quartos, ''), '([0-9]{1,2})', 'g') AS x$a$,
$b$  SELECT min(x[1]::int), max(x[1]::int) INTO v_q_min, v_q_max
    FROM regexp_matches(nai_numeros_por_extenso(coalesce(p_quartos, '')), '([0-9]{1,2})', 'g') AS x$b$);

CREATE OR REPLACE FUNCTION public.nai_numeros_por_extenso(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- 225: "dois quartos" -> "2 quartos"; "um ou dois" -> "1 ou 2"
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           lower(unaccent(coalesce(p, ''))),
           '\m(um|uma)\M', '1', 'g'), '\m(dois|duas)\M', '2', 'g'), '\mtres\M', '3', 'g'),
           '\mquatro\M', '4', 'g'), '\mcinco\M', '5', 'g'), '\mseis\M', '6', 'g');
$function$;

-- bairro parecido: >= 0,6 entra sem perguntar; 0,45-0,6 confirma (como antes)
SELECT pg_temp.trocar('nai_buscar_por_perfil(bigint,text,text,text,text)',
$a$      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN$a$,
$b$      -- 225: parecido o bastante entra sem perguntar (Pedro: "use palavras
      -- semelhantes em todos os parâmetros de filtros")
      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.60 THEN
        PERFORM nai_anotar(p_turno, 7, 'bairro_parecido', 'mudou', p_bairro || ' -> ' || v_perto);
        RETURN QUERY SELECT * FROM nai_buscar_por_perfil(p_turno, v_perto, p_teto, p_quartos, p_mobilia);
        RETURN;
      END IF;
      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN$b$);

-- tipo: apt, apê, apart., kitnet, studio, loft
SELECT pg_temp.trocar('nai_tipo_pedido(text)',
$a$    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'$a$,
$b$    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap|apt|apts|ape|apes|apart\w*|kitnet|kitnets|kitinete|quitinete|studio|studios|loft|lofts)\M' THEN 'Apartamento%'$b$);

-- negócio: financiamento e comprador são venda; inquilino, locatário e alugue são locação
SELECT pg_temp.trocar('nay_negocio_pedido(text)',
$a$  v boolean := t ~ '\m(venda|vender|vendas|comprar|compra|a venda|vendo)\M';
  l boolean := t ~ '\m(locacao|aluguel|alugar|aluga|alugado|locar)\M';$a$,
$b$  -- 225: palavras parecidas (financia -> venda; inquilino, alugue -> locação)
  v boolean := t ~ '\m(venda|vendas|vender|vende|vendo|vendido|vendida|comprar|compra|compro|comprador\w*|a venda|financi\w*|adquirir|investimento|investir)\M';
  l boolean := t ~ '\m(locacao|locacoes|aluguel|alugueis|alug\w*|locar|locado|locada|locatari\w*|inquilin\w*|para morar de aluguel)\M';$b$);

-- 4 ---------------------------------- "ALUGAR OU COMPRAR?" ANTES DO CARD
SELECT pg_temp.trocar('nai_filtro_ja_perguntado(bigint,text)',
$a$             WHEN 'abertura' THEN 'vou fazer um filtro com voc'$a$,
$b$             WHEN 'abertura' THEN 'vou fazer um filtro com voc'
             WHEN 'negocio'  THEN 'alugar ou (para )?comprar'  -- 225$b$);

CREATE OR REPLACE FUNCTION public.nai_negocio_antes_do_card(p_contato bigint, p_codigo integer, p_escreveu text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE i imoveis;
BEGIN
  -- 225 (Pedro, 30/09: "perguntar se é venda ou locação antes de mandar o card
  -- ou imóvel, para não confundir"). Só quando o imóvel serve aos dois E a
  -- conversa ainda não disse: imóvel de uma finalidade só, o card já diz.
  -- Uma vez em 24 h.
  IF p_codigo IS NULL OR nai_finalidade_do_imovel(p_codigo) <> 'ambos' THEN RETURN NULL; END IF;
  IF nai_negocio_da_conversa(p_contato, coalesce(p_escreveu, '')) IS NOT NULL THEN RETURN NULL; END IF;
  IF nai_filtro_ja_perguntado(p_contato, 'negocio') THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  RETURN 'O ' || coalesce(nai_condominio_ok(i.condominio_nome), 'imóvel ' || p_codigo)
         || ' está disponível para locação e para venda. O seu cliente quer alugar ou comprar?';
END;
$function$;

SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
$a$  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
$a$,
$b$  -- 14n ------------------------- ALUGAR OU COMPRAR, ANTES DO CARD (225)
  IF v_corretor AND NOT v_ident AND v_texto ~* 'C[óo]digo:\s*\d{3,5}'
     AND (SELECT count(*) FROM regexp_matches(v_texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
    v_novo := nai_negocio_antes_do_card(t.contato_id,
                (regexp_match(v_texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int, p_escreveu);
    IF v_novo IS NOT NULL THEN
      v_texto  := v_novo;
      v_ident  := true;
      v_guarda := coalesce(v_guarda || '+', '') || 'negocio_antes_do_card';
      PERFORM nai_anotar(p_turno, 14, 'negocio_antes_do_card', 'mudou', 'imóvel de locação e venda: perguntou qual dos dois');
    END IF;
  END IF;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
$b$);

SELECT pg_temp.trocar('nai_enfileirar_card(bigint,integer)',
$a$  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'card', 1);$a$,
$b$  -- 225: imóvel de locação e venda, conversa sem negócio: pergunta antes do card
  IF nai_negocio_antes_do_card(t.contato_id, p_codigo, t.texto) IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno',
      nai_negocio_antes_do_card(t.contato_id, p_codigo, t.texto), 'resposta', 1);
    PERFORM nai_anotar(p_turno, 14, 'negocio_antes_do_card', 'mudou', 'imóvel de locação e venda: perguntou qual dos dois');
    RETURN jsonb_build_object('ok', true, 'achou', true, 'fotos', 0, 'perguntou', 'negocio');
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'card', 1);$b$);

-- o prompt: depois do "alugar", o card
DO $$
DECLARE v_texto text; v_novo text; v_versao int;
  de text := '- Ele já pediu visita: vá para a etapa 5.';
  para text := '- Ele já pediu visita: vá para a etapa 5.' || E'\n'
    || '- O sistema perguntou se o cliente quer alugar ou comprar (imóvel que serve aos dois) e ele respondeu: chame imovel_por_codigo com o IMÓVEL DESTA CONVERSA e mande o card.';
BEGIN
  SELECT texto, versao INTO v_texto, v_versao FROM nai_prompt WHERE papel = 'corretor' FOR UPDATE;
  IF position(de IN v_texto) = 0 THEN RAISE EXCEPTION 'prompt do corretor: não achei "%"', de; END IF;
  v_novo := replace(v_texto, de, para);
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'Claude 30/09 (225): depois do "alugar ou comprar", o card');
  RAISE NOTICE 'prompt do corretor: versão % -> %', v_versao, v_versao + 1;
END $$;

-- 5 --------------------------------------------------------------- A BATERIA
SELECT pg_temp.trocar('nai_rodar_casos()',
$a$      WHEN 'foto'       THEN coalesce(nai_deve_mandar_fotos(NULL, '', c.frase), false)::text  -- 224$a$,
$b$      WHEN 'foto'       THEN coalesce(nai_deve_mandar_fotos(NULL, '', c.frase), false)::text  -- 224
      WHEN 'mais_em_conta' THEN nai_pede_mais_em_conta(c.frase)::text  -- 225
      WHEN 'extenso'    THEN nai_numeros_por_extenso(c.frase)  -- 225$b$);

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
  ('Pedro 30/09', 'pode ser mais em conta também', 'mais_em_conta', 'true', 'ele pediu mais em conta: sai da faixa para baixo'),
  ('Pedro 30/09', 'Até 4 mil Cliente quer outro padrão.', 'mais_em_conta', 'false', 'até 4 mil é faixa de 3.200 a 4.400'),
  ('Pedro 30/09', 'dois quartos', 'extenso', '2 quartos', 'quartos por extenso'),
  ('Pedro 30/09', 'um ou dois', 'extenso', '1 ou 2', 'quartos por extenso'),
  ('Pedro 30/09', 'tem apt de 2 quartos no Vieiralves?', 'tipo', 'Apartamento%', 'apt é apartamento'),
  ('Pedro 30/09', 'procuro kitnet na Cachoeirinha', 'tipo', 'Apartamento%', 'kitnet entra como apartamento'),
  ('Pedro 30/09', 'cliente quer financiar até 300 mil', 'negocio', 'venda', 'financiamento é venda'),
  ('Pedro 30/09', 'tenho um inquilino procurando 2 quartos', 'negocio', 'locacao', 'inquilino é locação'),
  ('Pedro 30/09', 'ela alugou um no ano passado e quer outro', 'negocio', 'locacao', 'alugou é locação');
COMMIT;
