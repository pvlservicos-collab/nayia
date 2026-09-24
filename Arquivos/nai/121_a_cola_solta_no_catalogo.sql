-- =====================================================================
-- NAI -- 121: a cola do cadastro solta quando ele pergunta do catalogo
--           (24/09/2026, achado na Rodada de treino 9)
--
-- MEDIDO na rodada 9, 47 casos reais de corretor:
--     o Jev e o banco concordaram ............ 29 casos,  1 calado
--     o Jev disse IMOVEIS e o banco mandou
--     para a secretaria ...................... 16 casos, 13 CALADOS
--     desses, com o Jev certo (>= 0,70) ....... 9 casos,  9 calados
--
-- A causa e a regra 3 do `nai_mente_registrar`, a cola do cadastro: ficha
-- aberta manda em TUDO por 24h, passando por cima da regra 2 ("fala de
-- imovel e da de imoveis"). Um corretor oferece um imovel dele de manha e
-- fica mudo o dia inteiro para pergunta de imovel -- e a secretaria, que
-- nao sabe falar de catalogo, nao responde nada.
--
-- Morreram assim, calados, na rodada:
--     "B dia! Envia o life parque dez p locacao pfv?"
--     "Tem smille mundi pra Mindu pra locacao?"
--     "Tem alguma opcao no Planalto, Lirio do vale? Ate 2.200"
--     "Gostaria de cancelar a visita de hoje"
--
-- A COLA CONTINUA, mas solta quando ele pergunta do NOSSO catalogo.
-- Medido: nenhuma resposta de cadastro ("apartamento", "3 quartos sendo 1
-- suite", "8 mil incluso condominio", "mobiliado", "no Vieiralves")
-- dispara os sinais -- o dialogo do cadastro segue inteiro.
-- Chave: `cola_solta_no_catalogo`.
--
-- 2. E O PRECO QUE VIRAVA CODIGO. "To buscando opcoes e 3500 E de 5000" --
-- ela leu 5000 como o imovel 5000 (Condominio Santa Clara) e escalou ao
-- Tel. `nay_tirar_valores` ja tira "de X a Y", mas nao a faixa invertida
-- "X e de Y". O "de" antes do segundo numero e o que marca preco: "me
-- manda o 5718 e o 5722" tem "e o", nao "e de", e continua passando.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('cola_solta_no_catalogo','sim')
ON CONFLICT (chave) DO NOTHING;

-- ---- 1. o sinal: ele esta perguntando do NOSSO catalogo? --------------
CREATE OR REPLACE FUNCTION public.nai_pergunta_de_catalogo(p_texto text)
 RETURNS boolean
 LANGUAGE sql STABLE
AS $function$
  WITH s AS (SELECT lower(unaccent(coalesce(p_texto,''))) AS t)
  SELECT coalesce(array_length(nai_imoveis_pedidos(p_texto, ''), 1), 0) > 0
      OR nai_pede_os_valores(p_texto)
      OR (SELECT t FROM s) ~ '\m(visita|visitar|visitamos|remarcar|cancelar|agendar)\M'
      -- "Tem smille mundi pra locacao?", "Vai ter a casa para locacao?"
      -- O segundo termo e so de BUSCA (locacao, venda, opcao, disponivel).
      -- Fora dele de proposito: quarto, casa, apartamento -- que e o
      -- vocabulario com que ele RESPONDE o cadastro ("tem 3 quartos").
      OR ((SELECT t FROM s) ~ '\m(tem|tens|teria|vai ter|voce tem|vc tem|possui|envia|enviar|manda|mandar|mostra|procuro|busco)\M'
          AND (SELECT t FROM s) ~ '\m(loca|alug|venda|vender|comprar|opc|disponiv)');
$function$;

-- ---- os casos, ainda vermelhos ---------------------------------------
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Rodada 9', 'Tem smille mundi pra Mindu pra locacao ?', 'catalogo', 'true',
  'pergunta de imovel solta a cola do cadastro'),
 ('Rodada 9', 'Vai ter a casa Para locacao no nova cidade?', 'catalogo', 'true',
  'pergunta de imovel solta a cola, mesmo sem citar codigo'),
 ('Rodada 9', 'Oi, boa tarde! Gostaria de cancelar a visita de hoje', 'catalogo', 'true',
  'assunto de visita e da de imoveis, nao da secretaria'),
 ('Cadastro', 'tem 3 quartos sendo 1 suite', 'catalogo', 'false',
  'resposta de cadastro NAO solta a cola'),
 ('Cadastro', '8 mil incluso condominio', 'catalogo', 'false',
  'valor do cadastro NAO solta a cola'),
 ('Cadastro', 'apartamento', 'catalogo', 'false',
  'o tipo dito no cadastro NAO solta a cola'),
 ('Rodada 9', 'Nay Tens a planilha ai de aluguel? To buscando opcoes e 3500 E de 5000',
  'imoveis', '{}',
  'faixa de preco invertida nao e codigo de imovel'),
 ('Tel', 'me manda o 5718 e o 5722', 'imoveis', '{5718,5722}',
  'dois codigos ditos na mao continuam sendo codigo');

CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'catalogo'   THEN nai_pergunta_de_catalogo(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'passe'      THEN nai_passe_do_citado(nai_imoveis_pedidos(c.frase, ''))::text
      WHEN 'texto_limpo' THEN nai_texto_sem_os_barrados(c.frase)
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

\echo '=== ANTES do conserto (tem que ter vermelho) ==='
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;


CREATE OR REPLACE FUNCTION public.nay_tirar_valores(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Cada linha é uma forma que aparece de verdade nas mensagens. Ordem
  -- importa: as mais específicas primeiro, senão a genérica come metade.
  -- Por último, a pontuação: vírgula/ponto que NÃO precede dígito é
  -- pontuação, não separador decimal. Sem isto "me manda o 3500, 3210 e
  -- 2943" perdia o 3500, porque a extração exige não-vírgula depois do
  -- número -- guarda que existe para não partir "4.000" ao meio.
  SELECT regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(
    regexp_replace(lower(coalesce(p_texto,'')),
    -- FAIXA INVERTIDA (121): "opcoes e 3500 E de 5000". O "de" antes do
    -- segundo numero e o que marca preco -- "me manda o 5718 e o 5722"
    -- tem "e o", nao "e de", e continua sendo codigo.
    '[0-9][0-9.,]*[ \t]*(a|e)[ \t]+de[ \t]+[0-9][0-9.,]*', ' ', 'g'),
    -- DOCUMENTO NAO E CODIGO (83): "CRECI 4321", "creci: 4321", "CPF 529.982.247-25".
    '\m(creci|cpf|rg|cnpj|cnh|matricula|matrícula|protocolo)\M[^0-9]{0,15}[0-9][0-9./-]*', ' ', 'g'),
    -- e TELEFONE: "(92) 98144-5964", "92 98144-5964", "98144-5964", "9 8144-5964"
    '(\(?[0-9]{2}\)?[ \t]*)?9?[ \t]?[0-9]{4}[ \t]?-[ \t]?[0-9]{4}\M', ' ', 'g'),
    -- ANO EM DATA nao e codigo (78): "maio 2028", "maio de 2028", "marco/2027".
    '\m(janeiro|fevereiro|mar[cç]o|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M[ \t]*(de[ \t]+|/[ \t]*)?(19|20)[0-9]{2}\M', ' ', 'g'),
    -- e data com barra: "05/2028", "10/05/2028", "10/05/28"
    '\m[0-9]{1,2}[ \t]*/[ \t]*([0-9]{1,2}[ \t]*/[ \t]*)?((19|20)[0-9]{2}|[0-9]{2})\M', ' ', 'g'),
    -- "entre 3000 e 5000", "de 2500 a 4000"
    '\m(entre|de)\s+[0-9][0-9.,]*\s*(a|e|至|ate|até)\s+[0-9][0-9.,]*', ' ', 'g'),
    -- "R$ 4.000", "R$4000", "$4000"
    '(r\$|\$)\s*[0-9][0-9.,]*', ' ', 'g'),
    -- "4000 reais", "4 mil", "400k", "4000 conto"
    '[0-9][0-9.,]*\s*(reais|real|contos?|mil|k)\M', ' ', 'g'),
    -- "até 4000", "no máximo 4000", "paga 4000", "orçamento de 4000"
    '\m(ate|at[ée]|m[aá]xim[oa]|min[ií]m[oa]|paga(r|ndo)?|pago|proposta|'
    'or[cç]amento|faixa|valor(es)?|limite|teto|budget|invest(ir|imento)?)\M'
    || '[ \t:=–-]*((r\$|\$)[ \t]*)?((de|por|a|at[eé]|em|custa|fica)[ \t]+)?((r\$|\$)[ \t]*)?' || '[0-9][0-9.,]*', ' ', 'g'),
    -- "aluguel de 3500", "venda por 450000", "condomínio 800"
    '\m(aluguel|loca[cç][aã]o|venda|condom[ií]nio|iptu|taxa|entrada|sinal|'
    'parcela|presta[cç][aã]o)\M' || '[ \t:=–-]*((r\$|\$)[ \t]*)?((de|por|a|at[eé]|em|custa|fica)[ \t]+)?((r\$|\$)[ \t]*)?' || '[0-9][0-9.,]*', ' ', 'g'),
    -- ÁREA não é código: "109m2", "88 m²", "120 metros". No card ela cai
    -- na mesma faixa dos códigos de 3 dígitos, e 11 imóveis têm código
    -- entre 100 e 999 -- colisão pequena, mas ela existe e é silenciosa.
    '[0-9][0-9.,]*\s*(m2|m²|mts?|metros?)\M', ' ', 'g'),
    -- número com separador de milhar nunca é código: "4.000", "4,500"
    '[0-9]+[.,][0-9]{3}\M', ' ', 'g'),
    '[.,](?![0-9])', ' ', 'g');
$function$;

CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text, p_motivo text, p_por text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_at text; v_motivo text; v_contato bigint; v_ficha bigint;
        v_texto text; v_antes text; v_por text; p jsonb;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
  v_motivo := left(coalesce(p_motivo, ''), 300);
  v_por := coalesce(p_por, 'mente');

  SELECT contato_id, texto INTO v_contato, v_texto FROM nai_turno WHERE id = p_turno;
  p := nai_pedido_do_turno(p_turno);

  -- 1. CORTESIA SEGUE COM QUEM JA ESTAVA (115).
  IF (p->>'cortesia')::boolean THEN
    SELECT t.atendente INTO v_antes FROM nai_turno t
     WHERE t.contato_id = v_contato AND t.id < p_turno
       AND t.criado_em > now() - interval '6 hours'
     ORDER BY t.id DESC LIMIT 1;
    IF v_antes IS NOT NULL AND v_antes <> v_at THEN
      v_at := v_antes; v_motivo := 'cortesia: segue com quem já atendia'; v_por := 'cola';
    END IF;
  END IF;

  -- 2. PEDIU IMOVEL, E DA DE IMOVEIS (117). A conferencia sobre a mente.
  IF v_at = 'secretaria'
     AND (p->>'de_imovel')::boolean
     AND NOT (p->>'oferta')::boolean
     AND NOT (p->>'link')::boolean THEN
    v_at := 'locacao';
    v_motivo := 'fala de imóvel: é da de imóveis (a mente disse: ' || left(v_motivo, 80) || ')';
    v_por := 'regra';
  END IF;

  -- 3. A COLA DO CADASTRO (99e): ficha aberta manda em tudo.
  SELECT n.id INTO v_ficha FROM nai_imovel_novo n
   WHERE n.contato_id = v_contato AND n.situacao = 'colhendo'
     AND n.criado_em > now() - interval '24 hours'
   ORDER BY n.id DESC LIMIT 1;
  -- A COLA SOLTA QUANDO ELE PERGUNTA DO NOSSO CATALOGO (121). Sem isto,
  -- quem ofereceu um imovel de manha ficava mudo o dia inteiro: 13 dos 16
  -- calados da Rodada de treino 9 sairam daqui.
  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    IF nai_cfg('cola_solta_no_catalogo','sim') = 'sim'
       AND nai_pergunta_de_catalogo(p->>'texto') THEN
      PERFORM nai_anotar(p_turno, 5, 'cola_soltou', 'passou',
                         'ficha ' || v_ficha || ' aberta, mas ele perguntou do catalogo');
    ELSE
      v_at := 'secretaria'; v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')'; v_por := 'cola';
    END IF;
  END IF;

  -- 4. OFERTA E LINK SAO DELA, sempre (97, 111).
  IF ((p->>'oferta')::boolean OR (p->>'link')::boolean) AND nai_secretaria_ligada() THEN
    v_at := 'secretaria';
    v_motivo := CASE WHEN (p->>'link')::boolean THEN 'link de catálogo' ELSE 'está oferecendo imóvel' END;
    v_por := 'regra';
  END IF;

  IF v_at = 'secretaria' AND NOT nai_secretaria_ligada() THEN
    v_at := 'locacao'; v_motivo := 'secretaria desligada';
  END IF;

  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por) VALUES (p_turno, v_at, v_motivo, v_por);
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || v_motivo || ')', ''));
  RETURN v_at;
END;
$function$;

\echo '=== DEPOIS do conserto ==='
SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

COMMIT;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='nao' WHERE chave='cola_solta_no_catalogo';
-- A cola volta a grudar em tudo, como antes. O limpador de valores desfaz
-- reaplicando a definicao anterior (guardada em tirar_atual.sql).
-- =====================================================================
