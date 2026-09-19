-- =====================================================================
-- NAI -- 40: a porta entende quem vem do grupo, e não larga a conversa
--            no meio (Tel, 15/09/2026)
--
-- Ele, sobre o contato novo que so disse "Boa noite!": "o filtro ai e marcar
-- mensagem nos grupos -- sempre as mensagens dos grupos sao de imoveis, entao
-- ela tem que responder o cumprimento e aguardar nesse caso".
-- E sobre as mensagens curtas no meio da conversa: "da um tempo para esperar as
-- mensagens todas do cliente, pode comecar com um cumprimento e depois aguarda
-- antes de responder de novo".
--
-- O QUE ESTAVA ACONTECENDO, medido nas primeiras horas no ar: 9 contatos novos
-- ficaram sem resposta, e a maioria NAO era cumprimento -- era gente no meio de
-- negociacao dizendo "Ate 400 mil", "Pode mandar", "Nao serve", "5 andar",
-- "Manha". A porta olhava cada mensagem SOZINHA: frase curta de continuidade
-- nao tem palavra de imovel, entao caia em "assunto que nao e de corretor".
--
-- TRES MUDANCAS:
--   1. quem MARCA uma mensagem do grupo esta falando de imovel -- e o filtro
--      que ele deu. Mesmo que escreva so "Boa noite!", a porta abre;
--   2. conversa que ELA JA ATENDEU continua dela. Isso ja valia para quem pediu
--      foto; agora vale tambem para o contato novo que ela atendeu -- e para no
--      instante em que o Tel digita, como ele definiu hoje de manha;
--   3. quando a pessoa so cumprimenta, o cabecalho manda responder o
--      cumprimento e ESPERAR -- em vez de despejar o roteiro em cima de quem
--      ainda nao disse o que quer.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado int DEFAULT NULL)
RETURNS TABLE(atende boolean, motivo text) LANGUAGE plpgsql AS $$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_humano timestamptz;
  v_id     bigint;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.id, c.liberado_em, c.humano_assumiu_em INTO v_id, v_lib, v_humano
    FROM nai_contato c WHERE c.chave = v_chave;

  -- MENSAGEM POR HUMANO PAUSA (Tel, 15/09). Vale antes de tudo.
  IF v_humano IS NOT NULL THEN
    RETURN QUERY SELECT false, 'o Tel escreveu nessa conversa'::text; RETURN;
  END IF;

  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa ja liberada'::text; RETURN;
  END IF;

  -- CONVERSA QUE ELA JA ATENDEU e dela ate o Tel digitar. Sem isto a porta
  -- julgava cada mensagem sozinha, e "pode mandar" -- resposta de quem esta
  -- negociando -- virava "assunto que nao e de corretor".
  IF v_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM nai_saida s
        WHERE s.contato_id = v_id
          AND s.papel_destino IN ('turno', 'corretor')
          AND s.estado IN ('enviado', 'enviando', 'simulado')
          AND s.criado_em > v_desde) THEN
    RETURN QUERY SELECT true, 'conversa que ela ja estava atendendo'::text; RETURN;
  END IF;

  -- MARCOU UMA MENSAGEM (o card do grupo, o imovel que ela mandou): e imovel,
  -- seja o que for que ele tenha escrito junto. E o filtro que o Tel deu.
  IF p_codigo_citado IS NOT NULL THEN
    RETURN QUERY SELECT true, 'marcou uma mensagem de imovel'::text; RETURN;
  END IF;

  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    IF nai_assunto_de_corretor(p_texto)
       OR (nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  v_cod := EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');

  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'pediu foto de um imovel'::text; RETURN;
  END IF;

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

-- ---------------------------------------------------------------------
-- SO CUMPRIMENTOU: responde o cumprimento e espera (Tel, 15/09).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_so_cumprimentou(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  -- Tem que ser SO isso: "boa noite, tem apartamento?" nao entra aqui, porque
  -- ali ele ja disse a que veio.
  -- Uma ou mais saudacoes emendadas: "oi", "boa noite!", "ola, tudo bem?".
  -- Escrever cada combinacao a mao deixava "ola, tudo bem?" de fora.
  SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) ~
         ('^((oi+|ola+|opa|eae|e ai|bom dia|boa tarde|boa noite|'
       || 'tudo bem|td bem|tudo bom|tudo certo|como vai|como esta|'
       -- o vocativo conta como parte do cumprimento: "Oi Nay" e so "oi"
       || 'nay|nay mendes|sra|sr|dona)'
       || '[\s,!.?]*)+$');
$$;

COMMENT ON FUNCTION nai_so_cumprimentou(text) IS
  'A mensagem e SO um cumprimento, sem pedido nenhum? Tel, 15/09.';
