# -*- coding: utf-8 -*-
"""Monta a 121 a partir das funcoes VIVAS do pg_proc (memoria: banco a frente
do repositorio). Uso: python montar121.py"""
import io

CAB = u"""-- =====================================================================
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

\\set ON_ERROR_STOP on

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
      OR (SELECT t FROM s) ~ '\\m(visita|visitar|visitamos|remarcar|cancelar|agendar)\\M'
      -- "Tem smille mundi pra locacao?", "Vai ter a casa para locacao?"
      -- O segundo termo e so de BUSCA (locacao, venda, opcao, disponivel).
      -- Fora dele de proposito: quarto, casa, apartamento -- que e o
      -- vocabulario com que ele RESPONDE o cadastro ("tem 3 quartos").
      OR ((SELECT t FROM s) ~ '\\m(tem|tens|teria|vai ter|voce tem|vc tem|possui|envia|enviar|manda|mandar|mostra|procuro|busco)\\M'
          AND (SELECT t FROM s) ~ '\\m(loca|alug|venda|vender|comprar|opc|disponiv)');
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

\\echo '=== ANTES do conserto (tem que ter vermelho) ==='
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

"""

RODAPE = u"""
\\echo '=== DEPOIS do conserto ==='
SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

COMMIT;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='nao' WHERE chave='cola_solta_no_catalogo';
-- A cola volta a grudar em tudo, como antes. O limpador de valores desfaz
-- reaplicando a definicao anterior (guardada em tirar_atual.sql).
-- =====================================================================
"""

VELHO_TIRAR = "    lower(coalesce(p_texto,'')),"
NOVO_TIRAR = (
    "    regexp_replace(lower(coalesce(p_texto,'')),\n"
    "    -- FAIXA INVERTIDA (121): \"opcoes e 3500 E de 5000\". O \"de\" antes do\n"
    "    -- segundo numero e o que marca preco -- \"me manda o 5718 e o 5722\"\n"
    "    -- tem \"e o\", nao \"e de\", e continua sendo codigo.\n"
    "    '[0-9][0-9.,]*[ \\t]*(a|e)[ \\t]+de[ \\t]+[0-9][0-9.,]*', ' ', 'g'),")

VELHA_COLA = """  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    v_at := 'secretaria'; v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')'; v_por := 'cola';
  END IF;"""

NOVA_COLA = """  -- A COLA SOLTA QUANDO ELE PERGUNTA DO NOSSO CATALOGO (121). Sem isto,
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
  END IF;"""


def main():
    tirar = io.open('tirar_atual.sql', encoding='utf-8').read().strip()
    assert tirar.count(VELHO_TIRAR) == 1, 'tirar: %d' % tirar.count(VELHO_TIRAR)
    tirar = tirar.replace(VELHO_TIRAR, NOVO_TIRAR)

    mente = io.open('mente_atual.sql', encoding='utf-8').read().strip()
    assert mente.count(VELHA_COLA) == 1, 'cola: %d' % mente.count(VELHA_COLA)
    mente = mente.replace(VELHA_COLA, NOVA_COLA)

    io.open('121_a_cola_solta_no_catalogo.sql', 'w', encoding='utf-8', newline='\n').write(
        CAB + "\n" + tirar + ";\n\n" + mente + ";\n" + RODAPE)
    print('escrito')


if __name__ == '__main__':
    main()
