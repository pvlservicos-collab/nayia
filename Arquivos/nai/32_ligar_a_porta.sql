-- =====================================================================
-- NAI -- 32: a porta de QUEM ELA ATENDE, ligada de verdade (Tel, 15/09/2026)
--
-- Ele: "quero que ative agora a nay la no whatsapp de aluguel somente para
-- novas conversas, incluindo pessoas que perguntam dos imoveis nos grupos ou no
-- pv perguntando especificamente dos imoveis; voce nao vai responder quem o tel
-- ja esta conversando, a nao ser que a pessoa peca especificamente fotos de um
-- imovel x ou peca imoveis claramente, as vezes com filtros".
-- E, perguntado: "me referi a quem chama dos grupos NO PV" e, sobre a conversa
-- liberada, "atendendo ate o tel mandar mensagem manualmente, mensagem por
-- humano pausa".
--
-- ACHADO QUE MUDA TUDO, medido antes de ligar: `nai_deve_atender` existia desde
-- 13/09 e NENHUM NO DO FLUXO A CHAMAVA. A chave `regra_publico` podia ser
-- ligada que nao mudava nada -- e ligar o modo 'todos' sem isto faria ela
-- responder TODO MUNDO, inclusive as conversas que o Tel esta tocando. A regra
-- estava escrita e morta.
--
-- Aqui ela passa a valer, por onde todo mundo ja passa: `nai_abrir_turno`
-- responde no cabecalho se atende (`cab.atende`) e por que (`cab.porta`), e o
-- roteador do fluxo so le esse campo.
--
-- O QUE MUDA NA REGRA DE 13/09:
--   1. conversa que ja existia tambem e liberada por PEDIDO CLARO DE IMOVEIS
--      ("tem apartamento em Ponta Negra ate 4 mil?"), nao so por pedido de
--      foto -- usa o mesmo detector do gatilho de busca;
--   2. quem o Tel assumiu (ele escreveu pelo celular) NAO e atendido, mesmo
--      liberado antes. "Mensagem por humano pausa."
-- =====================================================================

-- A porta. Devolve se atende e por que -- o motivo aparece no painel e no log,
-- e e ele que explica um silencio depois.
CREATE OR REPLACE FUNCTION nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado int DEFAULT NULL)
RETURNS TABLE(atende boolean, motivo text) LANGUAGE plpgsql AS $$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_humano timestamptz;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.liberado_em, c.humano_assumiu_em INTO v_lib, v_humano
    FROM nai_contato c WHERE c.chave = v_chave;

  -- MENSAGEM POR HUMANO PAUSA (Tel, 15/09). Vale antes de tudo: mesmo a
  -- conversa que ela ja tinha assumido volta a ser do Tel no instante em que
  -- ele digita. Para devolver a conversa a ela: DEVOLVER <telefone>.
  IF v_humano IS NOT NULL THEN
    RETURN QUERY SELECT false, 'o Tel escreveu nessa conversa'::text; RETURN;
  END IF;

  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa ja liberada'::text; RETURN;
  END IF;

  -- "Antigo" e QUALQUER historico anterior ao carimbo (Tel, 13/09: "qualquer
  -- historico, de qualquer epoca"), na Nay ou no numero do Tel.
  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    -- Gente nova: atende quando fala de imovel. Duvida pessoal, nao.
    --
    -- As DUAS perguntas, porque uma sozinha deixa buraco: a primeira olha as
    -- palavras do ramo (imovel, aluguel, visita, fotos...), a segunda reconhece
    -- um PEDIDO mesmo sem nenhuma dessas palavras. "Tem algo em Ponta Negra ate
    -- 4 mil?" nao diz "apartamento" nem "imovel" -- diz um bairro nosso e um
    -- valor, e ficava calada na primeira medicao.
    IF nai_assunto_de_corretor(p_texto)
       OR (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  -- ---------------- conversa que ja existia: so dois pedidos abrem a porta
  v_cod := p_codigo_citado IS NOT NULL
        OR EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');

  -- 1) foto de um imovel que da para identificar
  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu foto de um imovel'::text; RETURN;
  END IF;

  -- 2) pedido CLARO de imoveis, com ou sem filtro (Tel, 15/09: "ou peca
  --    imoveis claramente, as vezes com filtros, imoveis em tal lugar ou por
  --    tal valor"). O detector e o mesmo do gatilho de busca, ja medido contra
  --    as mensagens reais: "esse apartamento e mobiliado?" NAO entra aqui, e
  --    "tem apartamento em Ponta Negra ate 4 mil?" entra.
  IF (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu imoveis: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu imoveis'::text; RETURN;
  END IF;

  IF nai_pede_foto(p_texto) THEN
    RETURN QUERY SELECT false, 'pediu foto mas nao da para saber o imovel'::text; RETURN;
  END IF;
  RETURN QUERY SELECT false, 'conversa que ja existia: quem responde e o Tel'::text;
END;
$$;

COMMENT ON FUNCTION nai_deve_atender(text, text, int) IS
  'A porta: a Nay responde essa mensagem? Ligada por `regra_publico`. Tel, 15/09.';
