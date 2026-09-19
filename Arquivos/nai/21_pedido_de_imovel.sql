-- =====================================================================
-- NAI -- 21: o gatilho de PEDIDO DE IMOVEL sem referencia (Tel, 15/09/2026)
--
-- Ele: "fiz uma pergunta geral sem referenciar imoveis e ela não soube
-- responder: 'Boa tarde! Você tem apartamento no valor de R$ 350.000 de 2
-- quartos?'. Preciso que isso seja um outro gatilho de entrada, que ela
-- entenda que é quando alguem pede um imovel sem marcar nos grupos, e a ação
-- que ela deve tomar apos isso é começar as perguntas filtros".
--
-- O QUE ACONTECEU. A conversa tinha um imovel em andamento (o 5729), entao o
-- modelo leu a pergunta como sendo DAQUELE imovel, nao achou resposta e
-- chamou escalar_ao_tel. O corretor ficou sem resposta e o Tel recebeu um
-- recado que nao precisava existir: a pergunta nao era sobre imovel nenhum,
-- era uma BUSCA.
--
-- O QUE PASSA A VALER, em duas camadas:
--   1. o cabecalho do turno passa a DIZER que a mensagem e uma busca, com os
--      filtros que ele ja deu, e manda chamar buscar_por_perfil;
--   2. `nai_escalar` vira parede: pedido de busca nao sobe ao Tel, volta como
--      a primeira pergunta da sequencia.
-- A camada 2 existe porque instrucao o modelo pode ignorar -- parede, nao.
-- =====================================================================

-- ---------------------------------------------------------------------
-- O DETECTOR. Devolve o que a frase pediu, ou e_pedido=false.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_pedido_de_perfil(p_texto text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  s        text := lower(unaccent(coalesce(p_texto, '')));
  s_lugar  text := nay_normalizar_lugar(coalesce(p_texto, ''), true);
  v_busca  boolean;
  v_teto   numeric;
  v_q      int;
  v_bairro text;
  m        text[];
BEGIN
  -- ------------------------------------------------------ o BAIRRO primeiro
  -- Vem antes porque um bairro conhecido no texto ja e, sozinho, sinal de
  -- busca: "tem algo em Ponta Negra?" nao fala a palavra "apartamento".
  -- Casa o nome inteiro; e, para nome de tres palavras ou mais, as duas
  -- primeiras -- ninguem escreve "Parque 10 de Novembro" no WhatsApp.
  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;

  -- ------------------------------------------------------------ e uma BUSCA?
  -- Os parenteses em volta da concatenacao NAO sao enfeite: `~` e `||` tem a
  -- mesma precedencia no Postgres e a leitura e da esquerda para a direita,
  -- entao sem eles a regex vira so o primeiro pedaco -- e quebra.
  v_busca := s ~ ('\m(procuro|procurando|proucurando|busco|buscando|preciso de|precisa de|'
                 || 'teria|tem algum|tem alguma|tem algo|tem apartamento|tem apto|tem casa|tem kit|'
                 || 'voce tem|vc tem|vcs tem|voces tem|tens|quero um|quero uma|queria um|queria uma|'
                 || 'tenho cliente|meu cliente|cliente quer|cliente procura|cliente busca|'
                 || 'esta procurando|estao procurando|to procurando|estou procurando)\M');

  -- ...e fala de imovel, de um filtro, ou de um bairro nosso. Sem isto, "voce
  -- tem o contato do proprietario?" entraria aqui.
  v_busca := v_busca AND (
       s ~ ('\m(apartamento|apartamentos|apto|aptos|ap|casa|casas|kitnet|kitinete|quitinete|'
           || 'studio|estudio|flat|cobertura|sala|salas|imovel|imoveis|terreno|galpao|predio)\M')
    OR s ~ '\m\d+\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M'
    OR s ~ 'r\$'
    OR v_bairro IS NOT NULL
  );

  -- MAS nao e busca quando ele aponta para O imovel da conversa: "esse
  -- apartamento tem garagem?" e pergunta de ficha, e continua indo para a base.
  IF s ~ '\m(desse|deste|nesse|neste|esse|este|essa|esta|dele|dela|do imovel|no imovel)\M'
     AND NOT (s ~ '\m(outro|outros|outra|outras|mais algum|mais alguma|parecido|similar)\M') THEN
    v_busca := false;
  END IF;

  IF NOT v_busca THEN
    RETURN jsonb_build_object('e_pedido', false);
  END IF;

  -- --------------------------------------------------------------- QUARTOS
  m := regexp_match(s, '\m(\d+)\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M');
  IF m IS NOT NULL THEN v_q := m[1]::int; END IF;
  IF v_q IS NULL THEN
    m := regexp_match(s, '\m(um|uma|dois|duas|tres|quatro|cinco)\s+(quarto|quartos|dormitorio|dormitorios)\M');
    IF m IS NOT NULL THEN
      v_q := CASE m[1] WHEN 'um' THEN 1 WHEN 'uma' THEN 1 WHEN 'dois' THEN 2 WHEN 'duas' THEN 2
                       WHEN 'tres' THEN 3 WHEN 'quatro' THEN 4 ELSE 5 END;
    END IF;
  END IF;

  -- ------------------------------------------------------------------ TETO
  -- Em tres tentativas, da mais certa para a menos certa. O "de" solto ficou
  -- DE FORA de proposito: em "apartamento de 3 quartos" ele lia 3 como o
  -- orcamento do cliente, e foi exatamente o que aconteceu na primeira
  -- medicao. Numero colado a quarto, vaga, suite ou metro nunca e dinheiro.
  m := regexp_match(s, 'r\$\s*([\d\.,]+)\s*(mil|k)?');
  IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || coalesce(' ' || m[2], '')); END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m([\d\.,]+)\s*(mil|k)\M');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || ' mil'); END IF;
  END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m(ate|por|faixa de|em torno de|no maximo|maximo de)\s+([\d\.,]{3,})\s*(reais)?'
                         '(?!\s*(quarto|quartos|dormitorio|dormitorios|vaga|vagas|suite|suites|m2|metros))');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[2]); END IF;
  END IF;

  RETURN jsonb_build_object(
    'e_pedido', true,
    'teto',    v_teto,
    'quartos', v_q,
    'bairro',  v_bairro);
END;
$$;

COMMENT ON FUNCTION nai_pedido_de_perfil(text) IS
  'A mensagem e uma BUSCA de imovel (nao pergunta sobre o imovel da conversa)? Devolve os filtros que vieram junto. Tel, 15/09.';
