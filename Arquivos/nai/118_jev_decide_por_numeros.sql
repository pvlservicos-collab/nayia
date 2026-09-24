-- =====================================================================
-- NAI -- 118: o Jev no lugar da mente (Tel, 24/09/2026)
--
-- Ele: "quero implementar o jev como processador de mensagem para interpretar
-- melhor a imagem, ele e como a nay mestre, ele vai substituir ela na selecao
-- de agentes que ele chama e compreensao de mensagem".
--
-- O QUE MUDA. A mente era um modelo de texto devolvendo um JSON escrito por
-- ele -- e foi assim que ela passou dois dias mandando venda para a
-- secretaria, com o motivo "VENDA DE IMOVEL NAO E LOCACAO". O Jev
-- (typesafe/jev-1.13, pela OpenRouter) devolve NUMERO: para cada pergunta,
-- uma probabilidade. Em vez de ler a prosa do modelo, a gente compara com um
-- piso.
--
-- MEDIDO nos 10 casos reais destes dias, inclusive os 4 que a mente errava:
--     10 de 10 certos | US$ 0,000034 por mensagem
--
-- A DECISAO NAO E DE UMA RESPOSTA SO. No teste, "Tenho vivenda verde p
-- locacao tbm se precisar" deu atendente=secretaria com confianca 0,41 --
-- baixa -- mas oferta=0,77, que e o sinal que importa. E uma foto de anuncio
-- dele deu atendente=imoveis 0,60 com oferta=0,72. Por isso quem decide e a
-- COMBINACAO, aqui embaixo, e nao o campo `atendente` sozinho.
--
-- A IMAGEM. O Jev nao le imagem -- ele le o ESTADO que a gente monta. A
-- descricao que o GPT ja faz da foto entra nesse estado, e ai ele responde
-- "anuncio dele", "documento" ou "duvida sobre imovel nosso". Sem a
-- descricao, ele responde "nao da para saber" com 100% de certeza, em vez de
-- chutar -- que e o comportamento certo.
--
-- OS PISOS estao em `nai_config`, para o Tel mexer sem deploy.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES
  ('jev_piso_cortesia', '0.70'),
  ('jev_piso_oferta',   '0.60'),
  ('jev_piso_imovel',   '0.50')
ON CONFLICT (chave) DO NOTHING;

-- O que o Jev respondeu, guardado como veio: e por aqui que se afere o piso
-- depois, com caso real na mao.
CREATE TABLE IF NOT EXISTS nai_jev (
  id         bigserial PRIMARY KEY,
  turno_id   bigint REFERENCES nai_turno(id) ON DELETE CASCADE,
  respostas  jsonb NOT NULL,
  modelo     text,
  custo      numeric(12, 8),
  criado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nai_jev_turno ON nai_jev (turno_id);

-- ====================================================================
-- A DECISAO, por numero
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_decidir_com_jev(p_turno bigint, p_jev jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cortesia real; v_oferta real; v_atendente text; v_conf real;
  v_imagem text; v_tipo text; v_fin text;
  v_piso_c real := coalesce(nullif(nai_cfg('jev_piso_cortesia','0.70'),''),'0.70')::real;
  v_piso_o real := coalesce(nullif(nai_cfg('jev_piso_oferta','0.60'),''),'0.60')::real;
  v_escolha text; v_motivo text;
BEGIN
  INSERT INTO nai_jev (turno_id, respostas, modelo, custo)
       VALUES (p_turno, coalesce(p_jev, '{}'::jsonb),
               p_jev->>'modelo', (p_jev->>'custo')::numeric);

  v_cortesia  := coalesce((p_jev #>> '{cortesia,noul}')::real, 0);
  v_oferta    := coalesce((p_jev #>> '{oferta,noul}')::real, 0);
  v_atendente := p_jev #>> '{atendente,choice}';
  v_conf      := coalesce((p_jev #>> '{atendente,confidence}')::real, 0);
  v_imagem    := p_jev #>> '{o_que_mandou,choice}';
  v_tipo      := p_jev #>> '{tipo,choice}';
  v_fin       := p_jev #>> '{finalidade,choice}';

  -- 1. CORTESIA nao decide nada: quem decide e a conversa de antes. A regra
  --    e a mesma da 115; aqui ela ganha um numero em vez de uma regex.
  IF v_cortesia >= v_piso_c THEN
    v_escolha := 'locacao';   -- `nai_mente_registrar` troca pela conversa anterior
    v_motivo  := 'cortesia (' || round(v_cortesia::numeric, 2) || ')';

  -- 2. OFERTA E DA SECRETARIA, e este sinal vale MAIS que o campo
  --    `atendente`: no teste, oferta 0,77 com atendente=secretaria 0,41, e
  --    oferta 0,72 com atendente=imoveis 0,60. O sinal especifico ganha.
  ELSIF v_oferta >= v_piso_o OR v_imagem = 'anuncio_dele' THEN
    v_escolha := 'secretaria';
    v_motivo  := 'oferece imóvel dele (' || round(v_oferta::numeric, 2) || ')'
                 || CASE WHEN v_imagem = 'anuncio_dele' THEN ' + anúncio na foto' ELSE '' END;

  -- 3. O resto segue a escolha do Jev.
  ELSE
    v_escolha := CASE WHEN v_atendente = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
    v_motivo  := coalesce(v_atendente, 'sem resposta') || ' (' || round(v_conf::numeric, 2) || ')'
                 || coalesce(' · foto: ' || v_imagem, '');
  END IF;

  -- O TIPO E A FINALIDADE que o Jev leu entram como PISTA, nunca por cima do
  -- que a conversa ja dizia: `nai_pedido_do_turno` continua mandando.
  IF v_tipo IN ('casa', 'apartamento') AND nai_tipo_da_conversa(
       (SELECT contato_id FROM nai_turno WHERE id = p_turno),
       (SELECT texto FROM nai_turno WHERE id = p_turno)) IS NULL THEN
    PERFORM nai_anotar(p_turno, 5, 'jev_leu_o_tipo', 'passou',
                       'o Jev entendeu ' || v_tipo || ', e a conversa não dizia');
  END IF;

  -- E a decisao ainda passa pela conferencia do banco (117): fala de imovel e
  -- nao e oferta -> e da de imoveis, diga o Jev o que disser.
  RETURN nai_mente_registrar(p_turno, v_escolha, v_motivo, 'jev');
END;
$function$;

COMMIT;

SELECT 'pisos' AS o, chave, valor FROM nai_config WHERE chave LIKE 'jev_%' ORDER BY chave;
