-- =====================================================================
-- NAI -- 120f: a parede tambem le o texto (24/09/2026)
--
-- A conferencia da saida so olhava linha COM codigo -- card e foto. O texto
-- que a Nay escreve passava inteiro, sem ninguem ler.
--
-- E ela escreve codigo no texto. Medido nos 90 dias, no que de fato saiu:
--
--     12/09  "Tem! Alem do Solar da Praia e do Acquarelle, temos:
--              - 887 — Castelli em Ponta Negra
--              - 4455 — Jardim Europa em Ponta Negra"
--
-- O 4455 e IMOVEL DE PARCEIRO. A parede da parceria -- a regra mais dura do
-- Tel, "parceria nunca sai" -- estava de pe no card e furada no texto. Duas
-- vezes em 90 dias, num lugar onde ninguem ia procurar.
--
-- O QUE MUDA. A conferencia passa a ler as linhas de lista do texto
-- ("codigo — nome"). A linha de um imovel de parceiro ou fora do mercado e
-- retirada. Se depois disso a lista ficou vazia, a mensagem inteira e
-- barrada e o Tel avisado -- melhor calada do que oferecendo o que nao e
-- nosso.
--
-- SO LINHA DE LISTA, de proposito. Texto corrido que menciona um numero
-- nao e mexido: prefiro deixar passar um caso raro a picotar frase da Nay.
-- Chave: `conferencia_confere_texto`.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('conferencia_confere_texto', 'sim')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_imovel_barrado(p_codigo integer)
 RETURNS boolean
 LANGUAGE sql STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = p_codigo
                    AND (coalesce(i.e_parceiro, false)
                         OR NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)));
$function$;

-- Devolve o texto sem as linhas de lista que citam imovel barrado. Funcao
-- a parte para a bateria conseguir testar sem escrever no banco.
CREATE OR REPLACE FUNCTION public.nai_texto_sem_os_barrados(p_texto text)
 RETURNS text
 LANGUAGE plpgsql STABLE
AS $function$
DECLARE v_linha text; v_cod int; v_saida text[] := '{}'; v_tirou int := 0;
BEGIN
  IF p_texto IS NULL THEN RETURN NULL; END IF;
  FOREACH v_linha IN ARRAY string_to_array(p_texto, E'\n') LOOP
    v_cod := (regexp_match(v_linha, '\m(\d{3,5})\s*[—–-]\s*\w'))[1]::int;
    IF v_cod IS NOT NULL AND nai_imovel_barrado(v_cod) THEN
      v_tirou := v_tirou + 1;
      CONTINUE;
    END IF;
    v_saida := v_saida || v_linha;
  END LOOP;
  IF v_tirou = 0 THEN RETURN p_texto; END IF;
  RETURN array_to_string(v_saida, E'\n');
END;
$function$;

-- ---- o caso, antes do conserto -----------------------------------------
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Ponta Negra 12/09',
  E'Tem! Além do Solar da Praia e do Acquarelle, temos:\n• 887 — Castelli em Ponta Negra\n• 4455 — Jardim Europa em Ponta Negra',
  'texto_limpo',
  E'Tem! Além do Solar da Praia e do Acquarelle, temos:\n• 887 — Castelli em Ponta Negra',
  'imóvel de parceiro não sai nem escrito no meio do texto');

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

-- ---- a conferencia passa a chamar a limpeza ----------------------------
CREATE OR REPLACE FUNCTION public.nai_conferir_texto_da_saida(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r record; v_novo text; n int := 0;
BEGIN
  IF nai_cfg('conferencia_confere_texto', 'sim') <> 'sim' THEN RETURN 0; END IF;

  FOR r IN
    SELECT id, texto FROM nai_saida
     WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL
       AND papel_destino <> 'tel' AND texto ~ '\m\d{3,5}\s*[—–-]\s*\w'
  LOOP
    v_novo := nai_texto_sem_os_barrados(r.texto);
    CONTINUE WHEN v_novo = r.texto;

    -- sobrou lista? entao so tira a linha. Nao sobrou: a mensagem inteira sai.
    IF v_novo ~ '\m\d{3,5}\s*[—–-]\s*\w' THEN
      UPDATE nai_saida SET texto = v_novo WHERE id = r.id;
      PERFORM nai_anotar(p_turno, 23, 'texto_conferido', 'tirou linha',
                         'linha de imóvel de parceiro ou fora do mercado');
    ELSE
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'texto citava imóvel barrado'
       WHERE id = r.id;
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, segurei uma mensagem: ela ia listar imóvel de parceiro (ou fora do mercado) '
        || 'escrito no texto -- "' || left(r.texto, 200) || '". Não mandei nada.',
        'texto_com_imovel_barrado');
      PERFORM nai_anotar(p_turno, 23, 'texto_conferido', 'barrou', left(r.texto, 200));
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$function$;

\echo '=== a bateria ==='
SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

COMMIT;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='nao' WHERE chave='conferencia_confere_texto';
-- A funcao continua existindo e nao faz nada. Falta ainda ligar a chamada
-- em `nai_enfileirar_resposta` -- feito na 120g.
-- =====================================================================
