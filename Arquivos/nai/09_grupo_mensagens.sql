-- =====================================================================
-- NAI -- 09: cards de imovel vistos em GRUPO (13/09/2026)
--
-- O que o Tel viu: marcou no grupo o card do 4159 (Grand Prix), respondeu no
-- privado "Tem fotos?", e a Nay nao soube de qual imovel era.
--
-- O que era: a citacao so resolve pelo registro do publicador (`envios`), e
-- aquele card foi ENCAMINHADO pelo celular da Nay de Locacao. A Z-API nao avisa
-- o proprio numero do que ele posta pelo celular; quem viu o card, com o texto,
-- foi o numero da Captacao, que esta no mesmo grupo.
--
-- O que segura: todo card de imovel que aparece em grupo, em qualquer numero
-- nosso, fica aqui pelo ID da mensagem; `nay_imovel_da_citacao` procura aqui
-- quando `envios` nao tem. So grava -- nada responde, nada envia.
-- =====================================================================

CREATE TABLE IF NOT EXISTS grupo_mensagens (
  message_id  text PRIMARY KEY,
  grupo_id    text,
  grupo_nome  text,
  remetente   text,
  texto       text,
  codigo      int,          -- so quando o card tem UM codigo e ele existe no catalogo
  instancia   text,         -- por qual numero nosso a mensagem chegou
  recebida_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_mensagens_recebida ON grupo_mensagens (recebida_em DESC);

-- Chamada pelos webhooks (ramo so de gravacao). Mensagem sem "Codigo: NNNN" nao
-- e card de imovel e nem entra: grupo de corretor fala de tudo.
CREATE OR REPLACE FUNCTION nay_registrar_mensagem_grupo(p_message_id text, p_grupo_id text, p_grupo_nome text,
                                                        p_remetente text, p_texto text, p_instancia text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_cods text[]; v_cod int;
BEGIN
  -- Guarda CARD DE IMOVEL, nao a conversa do grupo. Duas formas:
  -- com "Codigo: NNNN" (o card que a gente posta) e sem codigo nenhum, escrito
  -- a mao (o Tel postou assim no Anunciar Easy em 13/09: "📍Residencial IBIZA
  -- FLEX / 2 quartos sendo 1 suite / 3.900"). No segundo caso o ID fica
  -- guardado com `codigo` nulo -- e o que permite amarrar depois.
  IF nullif(btrim(coalesce(p_message_id, '')), '') IS NULL
     OR NOT (coalesce(p_texto, '') ~* 'c[óo]digo:\s*\d{3,5}'
             OR (coalesce(p_texto, '') ~ '(📍|•|▪)'
                 AND coalesce(p_texto, '') ~* '(r\$|alug|quarto|su[íi]te|mobiliad|m2|m²)')) THEN
    RETURN NULL;
  END IF;
  SELECT array_agg(DISTINCT m[1]) INTO v_cods
    FROM regexp_matches(p_texto, 'C[óo]digo:\s*(\d{3,5})', 'gi') AS m;
  -- Dois codigos no mesmo texto: nao escolhe (a Nay pergunta, com a lista).
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
  END IF;
  INSERT INTO grupo_mensagens (message_id, grupo_id, grupo_nome, remetente, texto, codigo, instancia)
  VALUES (btrim(p_message_id), p_grupo_id, p_grupo_nome, p_remetente, left(p_texto, 2000), v_cod, p_instancia)
  ON CONFLICT (message_id) DO NOTHING;
  RETURN v_cod;
END;
$$;

-- A citacao passa a olhar TAMBEM o que foi visto no grupo (14/09). Ordem:
-- `envios` (o que nos mandamos, com ID), depois o texto da nossa saida, e por
-- fim o card visto no grupo. So responde quando o codigo e certo.
CREATE OR REPLACE FUNCTION nay_imovel_da_citacao(p_message_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_id   text := NULLIF(btrim(coalesce(p_message_id,'')), '');
  v_cod  text;
  v_cods text[];
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;

  SELECT e.codigo INTO v_cod
    FROM envios e
   WHERE e.message_id = v_id
   ORDER BY e.enviado_em DESC
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- Card visto em grupo (inclusive o que o Tel posta pelo celular dele).
  SELECT g.codigo::text INTO v_cod
    FROM grupo_mensagens g
   WHERE g.message_id = v_id AND g.codigo IS NOT NULL
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  v_cods := nay_codigos_da_saida(v_id);
  IF coalesce(array_length(v_cods,1),0) = 1 THEN
    -- Só existe se for imóvel de verdade: número solto num texto nosso
    -- pode ser qualquer coisa.
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN v_cod;
  END IF;

  RETURN NULL;
END;
$$;
