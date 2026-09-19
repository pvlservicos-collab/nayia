-- =====================================================================
-- NAI atendimento locacao -- 03: a caixa de saida e o CHECK DUPLO
--
-- Camadas, da mais funda para a mais rasa:
--   1. GATILHO na insercao (`nai_saida_validar`): a linha so entra se o
--      destino for PARTE daquela conversa ou visita. O telefone nunca vem de
--      quem enfileira: sai de `nai_contato` pelo id. Foto so entra se a URL
--      pertencer, no banco, ao codigo declarado.
--   2. LIBERACAO (`nai_liberar_saida`): na hora de mandar, confere de novo a
--      chave, aplica pausa, janela de horario, modo teste (e a parede de que
--      no teste nada sai para numero fora da lista), barra repeticao e barra
--      quem o Tel assumiu (`nai_contato.humano_assumiu_em`).
--   3. NO n8n, o no "Conferir cabecalho" recalcula a chave em JavaScript,
--      com outra implementacao, e compara. Divergiu = nao manda.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_saida_validar()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_chave text;
  v record;
  t record;
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  IF NEW.visita_id IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  END IF;
  IF NEW.turno_id IS NOT NULL THEN
    SELECT * INTO t FROM nai_turno WHERE id = NEW.turno_id;
  END IF;

  IF NEW.papel_destino = 'turno' THEN
    -- Resposta: so para quem escreveu aquele turno.
    IF t.id IS NULL OR t.contato_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: resposta do turno % para contato % que nao e o autor', NEW.turno_id, NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'corretor' THEN
    IF v.id IS NULL OR v.corretor_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o corretor da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'proprietario' THEN
    IF v.id IS NULL OR v.proprietario_id IS DISTINCT FROM NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o proprietario da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'motoboy' THEN
    IF v.id IS NULL OR v.motoboy_id IS DISTINCT FROM NEW.contato_id OR NOT nai_e_motoboy(v_chave) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o acompanhante da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'tel' THEN
    IF v_chave IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone')) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o Tel', NEW.contato_id;
    END IF;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    IF NEW.papel_destino NOT IN ('turno', 'corretor')
       OR (NEW.papel_destino = 'turno' AND t.papel NOT IN ('corretor', 'tel')) THEN
      RAISE EXCEPTION 'NAI saida: foto so vai para corretor';
    END IF;
    -- A COLAGEM conta como imagem daquele imovel (Tel, 12/09): ela e nossa,
    -- montada das 4 primeiras fotos, e mora em `imovel_colagem`, nao em
    -- `imovel_fotos`. O resto da parede continua igual: url que nao esteja
    -- num dos dois lugares nao sai.
    IF NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = NEW.codigo AND f.url = NEW.imagem_url)
       AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = NEW.codigo AND c.url = NEW.imagem_url) THEN
      RAISE EXCEPTION 'NAI saida: a foto % nao e do imovel %', NEW.imagem_url, NEW.codigo;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nai_saida_validar ON nai_saida;
CREATE TRIGGER nai_saida_validar BEFORE INSERT ON nai_saida
  FOR EACH ROW EXECUTE FUNCTION nai_saida_validar();

-- Ninguem muda o destino depois de enfileirado.
CREATE OR REPLACE FUNCTION nai_saida_imutavel()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.contato_id <> OLD.contato_id OR NEW.chave_destino <> OLD.chave_destino
     OR NEW.papel_destino <> OLD.papel_destino
     OR NEW.imagem_url IS DISTINCT FROM OLD.imagem_url OR NEW.codigo IS DISTINCT FROM OLD.codigo THEN
    RAISE EXCEPTION 'NAI saida: destino e conteudo de uma mensagem enfileirada nao mudam';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS nai_saida_imutavel ON nai_saida;
CREATE TRIGGER nai_saida_imutavel BEFORE UPDATE ON nai_saida
  FOR EACH ROW EXECUTE FUNCTION nai_saida_imutavel();

-- ------------------------------------------------------------ enfileirar
-- Atalhos. Todos passam pelo gatilho acima.
CREATE OR REPLACE FUNCTION nai_enfileirar_texto(
  p_turno bigint, p_visita bigint, p_contato bigint, p_papel text, p_texto text,
  p_motivo text, p_ordem int DEFAULT 0, p_apos timestamptz DEFAULT now())
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  IF p_contato IS NULL OR nullif(btrim(coalesce(p_texto, ''), ' ' || chr(9) || chr(10) || chr(13)), '') IS NULL THEN RETURN NULL; END IF;
  INSERT INTO nai_saida (turno_id, visita_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
       VALUES (p_turno, p_visita, p_contato, p_papel, '', 'texto', btrim(p_texto, ' ' || chr(9) || chr(10) || chr(13)), p_ordem, p_motivo, p_apos)
  RETURNING id INTO v_id;
  IF p_visita IS NOT NULL THEN
    PERFORM nai_evento(p_visita, 'mensagem_' || p_papel, p_motivo);
  END IF;
  RETURN v_id;
END;
$$;

-- Aviso ao Tel (o contato dele e criado na primeira vez).
CREATE OR REPLACE FUNCTION nai_avisar_tel(p_turno bigint, p_visita bigint, p_texto text, p_motivo text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_tel bigint := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
BEGIN
  RETURN nai_enfileirar_texto(p_turno, p_visita, v_tel, 'tel', p_texto, p_motivo, 900);
END;
$$;

-- --------------------------------------------------------------- liberar
-- Pega o que esta pronto para sair e devolve UMA linha por mensagem, ja
-- com o telefone final. p_turno = as mensagens daquele turno (resposta,
-- sai na hora); NULL = as que a propria NAI inicia (lembretes, avisos),
-- que respeitam a janela de horario.
CREATE OR REPLACE FUNCTION nai_liberar_saida(p_turno bigint)
RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb,
              codigo int, papel text, redirecionado boolean)
LANGUAGE plpgsql AS $$
#variable_conflict use_column
DECLARE
  r          record;
  v_modo     text := nai_cfg('modo', 'desligado');
  v_pausada  boolean := nai_cfg('pausada', 'sim') <> 'nao';
  v_simulado boolean := nai_cfg('envio_simulado', 'nao') = 'sim';
  v_testes   text[] := nai_chaves_teste();
  v_destino  text := nai_fone_envio(nai_cfg('telefone_teste_destino', ''));
  v_tel      text;
  v_texto    text;
  v_chave_c  text;
  v_bloq     text;
  v_redir    boolean;
  v_papel_t  text;
  v_etiqueta text;
  v_nome     text;
BEGIN
  FOR r IN
    SELECT s.* FROM nai_saida s
     WHERE s.estado = 'pendente'
       AND s.enviar_apos <= now()
       AND ((p_turno IS NOT NULL AND s.turno_id = p_turno)
         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval '3 minutes')
             AND (nai_dentro_da_janela() OR s.papel_destino = 'tel')))
     ORDER BY s.id
     LIMIT 80
     FOR UPDATE SKIP LOCKED
  LOOP
    v_bloq := NULL; v_redir := false; v_texto := r.texto; v_etiqueta := NULL;
    SELECT k.chave, k.telefone, coalesce(k.nome_completo, k.nome_whatsapp)
      INTO v_chave_c, v_tel, v_nome FROM nai_contato k WHERE k.id = r.contato_id;

    IF v_modo NOT IN ('teste', 'todos') THEN
      v_bloq := 'nai_desligada';
    ELSIF v_pausada THEN
      v_bloq := 'nai_pausada';
    ELSIF v_chave_c IS DISTINCT FROM r.chave_destino THEN
      v_bloq := 'contato_mudou';
    ELSIF r.papel_destino <> 'tel'
          AND (SELECT k2.humano_assumiu_em FROM nai_contato k2 WHERE k2.id = r.contato_id) IS NOT NULL
          AND NOT (r.papel_destino = 'turno' AND (SELECT t2.papel FROM nai_turno t2 WHERE t2.id = r.turno_id) = 'tel') THEN
      -- O TEL ASSUMIU esse chat: a NAI nao manda mais nada para essa pessoa
      -- (so a resposta a um comando do proprio Tel passa).
      v_bloq := 'tel_assumiu';
    ELSIF r.tipo = 'imagem'
          AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = r.codigo AND f.url = r.imagem_url)
          -- A COLAGEM tambem e imagem legitima daquele imovel (Tel, 12/09): ela
          -- nao esta em `imovel_fotos` -- e montada por nos e mora em
          -- `imovel_colagem`. Sem esta linha, toda colagem sairia bloqueada
          -- como "foto_nao_confere", que e a trava contra mandar a foto de um
          -- imovel no card de outro.
          AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = r.codigo AND c.url = r.imagem_url) THEN
      v_bloq := 'foto_nao_confere';
    -- REPETIDA: o mesmo texto para a mesma pessoa em 10 minutos não sai de novo.
    -- EXCEÇÃO (Tel, 14/09): as frases do "depois das fotos" são passo do
    -- roteiro, não repetição do modelo. Ela mandou a sugestão de visita às
    -- 20:12 e as fotos às 20:17 -- e "Ou se tiver alguma dúvida ou quiser mais
    -- imóveis..." saiu BLOQUEADA como repetida, logo depois das fotos.
    -- ...e só conta o que saiu DEPOIS do marco de conversa zerada (14/09): o
    -- pré-voo mandou as frases da sugestão em modo simulado, a conversa foi
    -- zerada, e no teste seguinte a mesma sugestão saiu BARRADA como repetida.
    -- Conversa zerada é conversa nova, também para esta trava.
    -- ...e mensagem de VISITA só é repetida se for da MESMA visita (14/09): dois
    -- pedidos de visita seguidos ao mesmo proprietário, com o mesmo texto, são
    -- duas visitas -- o segundo saía barrado e o proprietário nunca sabia.
    ELSIF r.tipo = 'texto' AND coalesce(r.motivo, '') <> 'depois_das_fotos' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'texto' AND s2.texto = r.texto
               AND s2.visita_id IS NOT DISTINCT FROM r.visita_id
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    ELSIF r.tipo = 'imagem' AND EXISTS (
            SELECT 1 FROM nai_saida s2
             WHERE s2.contato_id = r.contato_id AND s2.estado IN ('enviado', 'simulado')
               AND s2.tipo = 'imagem' AND s2.imagem_url = r.imagem_url
               AND s2.enviado_em > greatest(now() - interval '10 minutes',
                     coalesce((SELECT k3.zerado_em FROM nai_contato k3 WHERE k3.id = r.contato_id), '-infinity'::timestamptz))) THEN
      v_bloq := 'repetida';
    END IF;

    -- MODO TESTE: o que iria para proprietario, Fernando ou Tel vai para o
    -- numero de teste, com a etiqueta de para quem iria.
    IF v_bloq IS NULL AND v_modo = 'teste' THEN
      IF r.papel_destino IN ('proprietario', 'motoboy', 'tel') THEN
        v_redir := true;
        v_etiqueta := '🧪 TESTE · iria para o ' ||
          CASE r.papel_destino WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN 'FERNANDO (motoboy)' ELSE 'TEL' END ||
          coalesce(' ' || v_nome, '') ||
          coalesce(' · visita #' || r.visita_id, '') || E'\n' ||
          CASE r.papel_destino
            WHEN 'proprietario' THEN 'Para responder como proprietário: MARQUE esta mensagem, ou comece com P:'
            WHEN 'motoboy' THEN 'Para responder como Fernando: MARQUE esta mensagem, ou comece com M:'
            ELSE 'Para responder como Tel: comece com T:' END || E'\n\n';
        v_tel := v_destino;
      ELSIF r.papel_destino = 'turno' THEN
        SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
        IF v_papel_t IN ('proprietario', 'motoboy', 'tel') THEN
          v_etiqueta := '🧪 (resposta ao ' ||
            CASE v_papel_t WHEN 'proprietario' THEN 'PROPRIETÁRIO' WHEN 'motoboy' THEN 'FERNANDO' ELSE 'TEL' END || E')\n';
        END IF;
        -- TODAS AS MENSAGENS NO CHAT DELE (Tel, 13/09: "quero que as mensagens
        -- vao todas para mim, corretores, proprietarios e tal nesse teste"). O
        -- que iria para outro numero -- um corretor simulado, por exemplo --
        -- chega no numero de teste com a etiqueta de para quem iria. Antes isso
        -- morria como 'teste_fora_da_lista' e ele nao via a mensagem.
        IF nai_chave(v_tel) IS DISTINCT FROM nai_chave(v_destino) THEN
          v_redir := true;
          v_etiqueta := coalesce(v_etiqueta, '') || '🧪 TESTE · iria para o ' ||
            CASE coalesce(v_papel_t, 'corretor')
              WHEN 'proprietario' THEN 'PROPRIETÁRIO'
              WHEN 'motoboy' THEN 'FERNANDO (motoboy)'
              WHEN 'tel' THEN 'TEL'
              ELSE 'CORRETOR' END ||
            coalesce(' ' || v_nome, '') || ' ' || nai_fone_fmt(v_tel) || E'\n\n';
          v_tel := v_destino;
        END IF;
      END IF;
      -- PAREDE DO TESTE: nada sai para numero fora da lista de teste.
      IF NOT (nai_chave(v_tel) = ANY (v_testes)) THEN
        v_bloq := 'teste_fora_da_lista';
      END IF;
    END IF;

    IF v_bloq IS NOT NULL THEN
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = v_bloq, telefone_final = v_tel, enviado_em = now()
       WHERE s.id = r.id;
      CONTINUE;
    END IF;

    IF r.tipo = 'texto' AND v_etiqueta IS NOT NULL THEN
      v_texto := v_etiqueta || v_texto;
    END IF;

    IF v_simulado THEN
      UPDATE nai_saida s SET estado = 'simulado', telefone_final = v_tel, redirecionado = v_redir,
                             enviado_em = now(), resposta = jsonb_build_object('texto_final', v_texto)
       WHERE s.id = r.id;
      IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
        UPDATE nai_visita SET ult_msg_prop_em = now() WHERE nai_visita.id = r.visita_id;
      ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
        UPDATE nai_visita SET ult_msg_moto_em = now() WHERE nai_visita.id = r.visita_id;
      END IF;
      CONTINUE;
    END IF;

    UPDATE nai_saida s SET estado = 'enviando', telefone_final = v_tel, redirecionado = v_redir
     WHERE s.id = r.id;

    id := r.id;
    rota := CASE r.tipo WHEN 'imagem' THEN 'send-image' ELSE 'send-text' END;
    telefone := v_tel;
    chave_esperada := nai_chave(v_tel);
    corpo := CASE r.tipo
               WHEN 'imagem' THEN jsonb_build_object('phone', v_tel, 'image', r.imagem_url)
               ELSE jsonb_build_object('phone', v_tel, 'message', v_texto) END;
    codigo := r.codigo;
    papel := r.papel_destino;
    redirecionado := v_redir;
    RETURN NEXT;
  END LOOP;
END;
$$;

-- -------------------------------------------------------------- confirmar
-- Grava o resultado de cada envio. Com o ID da mensagem, alimenta
-- `mensagem_saida` e `envios` -- e com isso a citacao (o corretor marca
-- a mensagem) e o "ficou de enviar" da Nay antiga continuam funcionando.
CREATE OR REPLACE FUNCTION nai_confirmar_envio(p_id bigint, p_resposta jsonb)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  r      record;
  v_mid  text := coalesce(p_resposta->>'messageId', p_resposta->>'id', p_resposta->>'zaapId');
  v_cod  int;
  v_papel_t text;
BEGIN
  SELECT * INTO r FROM nai_saida WHERE id = p_id;
  IF r.id IS NULL THEN RETURN 'nao_existe'; END IF;
  IF r.estado <> 'enviando' THEN RETURN 'ja_tratada'; END IF;

  IF nullif(btrim(coalesce(v_mid, '')), '') IS NULL THEN
    UPDATE nai_saida SET estado = 'erro', resposta = p_resposta, enviado_em = now() WHERE id = p_id;
    RETURN 'erro';
  END IF;

  UPDATE nai_saida SET estado = 'enviado', message_id = v_mid, resposta = p_resposta, enviado_em = now()
   WHERE id = p_id;

  INSERT INTO mensagem_saida (message_id, telefone, texto)
       VALUES (v_mid, r.telefone_final, coalesce(r.texto, r.imagem_url))
  ON CONFLICT (message_id) DO NOTHING;

  -- Card de imovel mandado a corretor vira linha em `envios` (o codigo sai
  -- do TEXTO desta mensagem, como no `Registrar saida` da Nay antiga).
  SELECT t.papel INTO v_papel_t FROM nai_turno t WHERE t.id = r.turno_id;
  IF r.tipo = 'texto' AND NOT r.redirecionado
     AND (r.papel_destino = 'corretor' OR (r.papel_destino = 'turno' AND v_papel_t = 'corretor')) THEN
    v_cod := (regexp_match(r.texto, 'C[oó]digo:\s*(\d{3,5})'))[1]::int;
    IF v_cod IS NOT NULL THEN
      INSERT INTO envios (codigo, telefone, destino, valor_enviado, message_id)
      SELECT i.codigo, r.telefone_final, 'corretor', coalesce(i.valor_aluguel, i.valor_venda, 0), v_mid
        FROM imoveis i WHERE i.codigo = v_cod;
    END IF;
  END IF;

  -- Marca na visita quando falamos com proprietario / Fernando.
  IF r.visita_id IS NOT NULL AND r.papel_destino = 'proprietario' THEN
    UPDATE nai_visita SET ult_msg_prop_em = now(), atualizado_em = now() WHERE id = r.visita_id;
  ELSIF r.visita_id IS NOT NULL AND r.papel_destino = 'motoboy' THEN
    UPDATE nai_visita SET ult_msg_moto_em = now(), atualizado_em = now() WHERE id = r.visita_id;
  END IF;
  RETURN 'enviado';
END;
$$;

-- Mensagem que o no "Conferir cabecalho" recusou.
CREATE OR REPLACE FUNCTION nai_registrar_bloqueio(p_id bigint, p_motivo text)
RETURNS void LANGUAGE sql AS $$
  UPDATE nai_saida SET estado = 'bloqueado', bloqueio = p_motivo, enviado_em = now()
   WHERE id = p_id AND estado = 'enviando';
$$;
