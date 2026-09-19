-- =====================================================================
-- NAI atendimento locacao -- 08: a AGENDA (roda de minuto em minuto)
--
-- Olha cada visita aberta e enfileira o que venceu. Cada acao tem sua
-- coluna de carimbo, gravada na MESMA transacao em que a mensagem entra na
-- fila -- entao nada sai duas vezes, mesmo com duas batidas simultaneas
-- (FOR UPDATE SKIP LOCKED).
-- As mensagens que a NAI inicia so saem dentro da janela de horario (quem
-- segura e o `nai_liberar_saida`); aqui so se decide O QUE e QUANDO.
-- =====================================================================

CREATE OR REPLACE FUNCTION nai_intervalo_dados(p_quando timestamptz)
RETURNS interval LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_quando - now() > interval '24 hours' THEN interval '60 minutes'
    WHEN p_quando - now() > interval '6 hours'  THEN interval '30 minutes'
    WHEN p_quando - now() > interval '2 hours'  THEN interval '10 minutes'
    ELSE interval '3 minutes' END;
$$;

CREATE OR REPLACE FUNCTION nai_inicio_periodo(p_quando timestamptz)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT ((l::date + nai_cfg(CASE WHEN extract(hour FROM l) < 12 THEN 'inicio_manha'
                                  WHEN extract(hour FROM l) < 18 THEN 'inicio_tarde'
                                  ELSE 'inicio_noite' END, '08:00')::time) AT TIME ZONE 'America/Manaus')
    FROM (SELECT p_quando AT TIME ZONE 'America/Manaus' AS l) t;
$$;

CREATE OR REPLACE FUNCTION nai_agenda_tick()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  v        nai_visita;
  c        nai_contato;
  n        int := 0;
  v_nome   text;
  v_falta  text[];
  d        record;
  v_reenv  interval := make_interval(mins => nai_cfg_int('reenvio_proprietario_min', 30));
  v_rmoto  interval := make_interval(mins => nai_cfg_int('reenvio_motoboy_min', 30));
  v_max    int := nai_cfg_int('reenvios_proprietario_max', 3);
  v_tel_h  interval := make_interval(hours => nai_cfg_int('aviso_tel_horas_antes', 2));
  v_lemb   interval := make_interval(mins => nai_cfg_int('lembrete_corretor_min', 60));
  v_moto   interval := make_interval(mins => nai_cfg_int('aviso_motoboy_min', 30));
  v_pos    interval := make_interval(mins => nai_cfg_int('pos_visita_min', 60));
  v_ini    timestamptz;
BEGIN
  UPDATE nai_config SET valor = to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'), atualizado_em = now()
   WHERE chave = '_agenda_rodou_em';
  IF NOT FOUND THEN
    INSERT INTO nai_config (chave, valor, descricao)
    VALUES ('_agenda_rodou_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI:SS'),
            'Carimbo: a ultima vez que a agenda da NAI rodou (so leitura).')
    ON CONFLICT (chave) DO NOTHING;
  END IF;
  IF nai_cfg('modo', 'desligado') NOT IN ('teste', 'todos') THEN RETURN 0; END IF;

  FOR v IN
    SELECT * FROM nai_visita
     WHERE estado NOT IN ('encerrada', 'cancelada', 'expirada')
     ORDER BY quando
     FOR UPDATE SKIP LOCKED
  LOOP
    SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
    v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));

    -- ---------------------------------------------- passou da hora sem fechar
    IF v.estado IN ('coletando', 'aguardando_proprietario', 'negociando', 'aguardando_acesso', 'aguardando_motoboy', 'com_tel')
       AND v.quando IS NOT NULL AND now() >= v.quando THEN
      UPDATE nai_visita SET estado = 'expirada', aguardando = NULL, senha = NULL, encerrada_em = now(), atualizado_em = now()
       WHERE id = v.id;
      PERFORM nai_evento(v.id, 'expirada', v.estado);
      -- Visita que estava COM O TEL (urgente, por exemplo) nao leva "nao
      -- consegui fechar" ao corretor: quem estava tratando era ele.
      IF v.estado <> 'com_tel' THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'não consegui fechar a visita de ' || nai_quando_humano(v.quando) || ' a tempo, desculpa. Quer tentar outro horário?',
          'expirada', 1);
      END IF;
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || ') chegou no horário sem fechar (estava: ' || v.estado || '). Avisei o corretor.', 'expirada');
      n := n + 1;
      CONTINUE;
    END IF;

    -- ---------------------------------------------- faltam dados (coletando)
    IF v.estado = 'coletando' AND v.proximo_lembrete_dados_em IS NOT NULL AND now() >= v.proximo_lembrete_dados_em THEN
      SELECT * INTO d FROM nai_dados_corretor(v.corretor_id);
      v_falta := ARRAY_REMOVE(ARRAY[
        CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
        CASE WHEN d.cpf IS NULL THEN 'seu CPF' END,
        CASE WHEN d.creci IS NULL THEN 'seu CRECI' END,
        CASE WHEN v.visitante_nome IS NULL THEN 'o nome completo do visitante' END,
        CASE WHEN v.visitante_cpf IS NULL THEN 'o CPF do visitante' END], NULL);
      IF coalesce(array_length(v_falta, 1), 0) = 0 THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
      ELSIF v.lembretes_dados >= nai_cfg_int('dados_lembretes_max', 3) OR now() >= v.quando - interval '1 hour' THEN
        UPDATE nai_visita SET proximo_lembrete_dados_em = NULL, aviso_tel_dados_em = now() WHERE id = v.id;
        IF v.aviso_tel_dados_em IS NULL THEN
          PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o corretor ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' ||
            nai_fone_fmt(c.telefone) || ') pediu visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) ||
            ', e não mandou: ' || array_to_string(v_falta, ', ') || '. Parei de cobrar. Visita #' || v.id || '.', 'dados_sem_resposta');
        END IF;
      ELSE
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita 😉', 'dados_falta', 1);
        UPDATE nai_visita SET lembretes_dados = lembretes_dados + 1,
                              proximo_lembrete_dados_em = now() + nai_intervalo_dados(v.quando)
         WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- proprietario sem responder
    IF v.aguardando = 'proprietario' AND v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em) THEN

      -- Hora marcada pelo Tel (VISITA <id> AVISA 10h).
      IF v.proximo_aviso_prop_em IS NOT NULL AND now() >= v.proximo_aviso_prop_em THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
          'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
          nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete_tel', 1);
        UPDATE nai_visita SET proximo_aviso_prop_em = NULL, aviso_tel_em = NULL, ult_msg_prop_em = now(),
                              reenvios_prop = reenvios_prop + 1 WHERE id = v.id;
        n := n + 1;
        CONTINUE;
      END IF;

      IF now() >= v.ult_msg_prop_em + v_reenv THEN
        IF v.reenvios_prop < v_max AND v.proximo_aviso_prop_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.proprietario_id, 'proprietario',
            'Oi' || coalesce(', ' || nai_vocativo(v.proprietario_nome), '') || ', passando de novo sobre a visita de ' ||
            nai_quando_humano(v.quando) || '. Consegue me confirmar?', 'p_lembrete', 1);
          UPDATE nai_visita SET reenvios_prop = reenvios_prop + 1, ult_msg_prop_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
        -- Depois do primeiro reenvio sem resposta, o corretor sabe da demora.
        IF v.reenvios_prop >= 1 AND v.aviso_demora_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
            coalesce(v_nome || ', ', '') || 'ainda estou aguardando o retorno do proprietário. Assim que ele responder eu te aviso, tá?',
            'p_avisa', 2);   -- card p_avisa: aqui quem esta devendo e o proprietario, nao o Tel
          UPDATE nai_visita SET aviso_demora_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
        -- Esgotou os reenvios: o Tel.
        IF v.reenvios_prop >= v_max AND v.aviso_tel_em IS NULL AND v.proximo_aviso_prop_em IS NULL THEN
          PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o proprietário do ' || nai_ref_imovel(v.codigo) || ' não responde sobre a visita #' ||
            v.id || ' (' || nai_hora_exata(v.quando) || '). Já mandei ' || (v.reenvios_prop + 1) || ' mensagens.' ||
            E'\nQuer que eu mande o próximo aviso que horas? Responda VISITA ' || v.id || ' AVISA 10h, ou VISITA ' || v.id ||
            ' OK se você confirmou por telefone.', 'p_sem_resposta');
          UPDATE nai_visita SET aviso_tel_em = now() WHERE id = v.id;
          n := n + 1;
        END IF;
      END IF;

      -- Faltando 2h e ainda sem confirmacao: o Tel (card "acionar o Tel").
      IF now() >= v.quando - v_tel_h AND v.aviso_tel_em IS NULL THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, a visita #' || v.id || ' no ' || nai_ref_imovel(v.codigo) || ' é ' ||
          nai_hora_exata(v.quando) || ' e o proprietário ainda não confirmou.' ||
          E'\nQue horas eu mando o próximo aviso? Responda VISITA ' || v.id || ' AVISA 10h — se ele não responder em ' ||
          nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos, te aviso para ligar. Ou VISITA ' || v.id || ' OK se já confirmou.',
          'p_tel_2h');
        UPDATE nai_visita SET aviso_tel_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
    END IF;

    -- Depois do aviso marcado pelo Tel, sem resposta: "pode ligar".
    IF v.aguardando = 'proprietario' AND v.reenvios_prop > 0 AND v.aviso_tel_em IS NULL AND v.proximo_aviso_prop_em IS NULL
       AND v.ult_msg_prop_em IS NOT NULL AND now() >= v.ult_msg_prop_em + v_reenv
       AND (v.ult_resp_prop_em IS NULL OR v.ult_resp_prop_em < v.ult_msg_prop_em)
       AND EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'mensagem_proprietario' AND e.detalhe = 'p_lembrete_tel'
                    AND e.quando >= v.ult_msg_prop_em - interval '1 minute') THEN
      PERFORM nai_avisar_tel(NULL, v.id, 'Tel, mandei o aviso ao proprietário da visita #' || v.id || ' e ele não respondeu em ' ||
        nai_cfg_int('reenvio_proprietario_min', 30) || ' minutos. Pode ligar para ele?', 'p_ligar');
      UPDATE nai_visita SET aviso_tel_em = now() WHERE id = v.id;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- Fernando sem responder
    IF v.estado = 'aguardando_motoboy' AND v.ult_msg_moto_em IS NOT NULL
       AND (v.ult_resp_moto_em IS NULL OR v.ult_resp_moto_em < v.ult_msg_moto_em)
       AND now() >= v.ult_msg_moto_em + v_rmoto THEN
      IF v.reenvios_moto < 1 THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          'Fernando, consegue me confirmar a visita do ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '?',
          'motoboy_lembrete', 1);
        UPDATE nai_visita SET reenvios_moto = reenvios_moto + 1, ult_msg_moto_em = now() WHERE id = v.id;
      ELSIF v.aviso_tel_moto_em IS NULL THEN
        PERFORM nai_avisar_tel(NULL, v.id, 'Tel, o Fernando não confirmou a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) ||
          ', ' || nai_hora_exata(v.quando) || '). O proprietário já confirmou. Responda VISITA ' || v.id || ' FERNANDO OK quando ele confirmar.',
          'motoboy_sem_resposta');
        UPDATE nai_visita SET aviso_tel_moto_em = now() WHERE id = v.id;
      END IF;
      n := n + 1;
    END IF;

    -- ---------------------------------------------- visita confirmada
    IF v.estado = 'confirmada' THEN
      v_ini := nai_inicio_periodo(v.quando);
      -- No comeco do periodo (se ficar a mais de 1h da visita).
      IF v.lembrete_periodo_em IS NULL AND now() >= v_ini AND v_ini <= v.quando - v_lemb
         AND v.confirmada_em < v_ini AND now() < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'passando pra lembrar da visita ' || nai_quando_humano(v.quando) || ' no ' ||
          nai_ref_imovel(v.codigo) || '. O Fernando te encontra lá 😉', 'lembrete_periodo', 1);
        UPDATE nai_visita SET lembrete_periodo_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 1 hora antes (se a confirmacao nao foi ja dentro dessa hora).
      IF v.lembrete_1h_em IS NULL AND now() >= v.quando - v_lemb AND now() < v.quando AND v.confirmada_em < v.quando - v_lemb THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          coalesce(v_nome || ', ', '') || 'daqui a 1 hora, às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') ||
          ', é a visita no ' || nai_ref_imovel(v.codigo) || '. O Fernando te encontra lá 😉 Qualquer imprevisto me avisa por aqui.', 'lembrete_1h', 1);
        UPDATE nai_visita SET lembrete_1h_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- 30 min antes: senha (fechadura) ou conferir a chave, com o Fernando.
      IF v.aviso_motoboy_em IS NULL AND now() >= v.quando - v_moto AND now() < v.quando AND v.motoboy_id IS NOT NULL THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
          CASE v.acesso
            WHEN 'fechadura' THEN 'Fernando, a senha da fechadura do ' || nai_ref_imovel(v.codigo) || ' é ' || coalesce(v.senha, '(peça ao Tel)') ||
                                  '. A visita é às ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. Conseguiu anotar?'
            WHEN 'proprietario_acompanha' THEN 'Fernando, lembrete: visita no ' || nai_ref_imovel(v.codigo) || ' às ' ||
                                  to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '. O proprietário vai estar lá.'
            ELSE 'Fernando, só confirmando: você já está com a chave do ' || nai_ref_imovel(v.codigo) || ' pra visita das ' ||
                 to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || '?' ||
                 CASE WHEN v.acesso = 'buscar_chave' THEN ' Depois não esquece de devolver ao proprietário.' ELSE '' END END,
          'aviso_motoboy', 1);
        UPDATE nai_visita SET aviso_motoboy_em = now() WHERE id = v.id;
        n := n + 1;
      END IF;
      -- Depois da visita: como foi? (e a senha sai do banco).
      IF v.pos_visita_em IS NULL AND now() >= v.quando + v_pos THEN
        PERFORM nai_enfileirar_texto(NULL, v.id, v.corretor_id, 'corretor',
          'E aí' || coalesce(', ' || v_nome, '') || ', como foi a visita no ' || nai_ref_imovel(v.codigo) || '? O cliente gostou?',
          'pos_visita', 1);
        IF v.acesso = 'buscar_chave' AND v.motoboy_id IS NOT NULL AND v.devolver_chave_em IS NULL THEN
          PERFORM nai_enfileirar_texto(NULL, v.id, v.motoboy_id, 'motoboy',
            'Fernando, não esquece de devolver a chave do ' || nai_ref_imovel(v.codigo) || ' ao proprietário.', 'devolver_chave', 2);
          UPDATE nai_visita SET devolver_chave_em = now() WHERE id = v.id;
        END IF;
        UPDATE nai_visita SET pos_visita_em = now(), estado = 'realizada', senha = NULL, atualizado_em = now() WHERE id = v.id;
        PERFORM nai_evento(v.id, 'realizada', NULL);
        n := n + 1;
      END IF;
    END IF;

    -- Realizada ha mais de 2 dias sem retorno: encerra.
    IF v.estado = 'realizada' AND now() >= coalesce(v.pos_visita_em, v.quando) + interval '2 days' THEN
      UPDATE nai_visita SET estado = 'encerrada', encerrada_em = now(), senha = NULL WHERE id = v.id;
    END IF;
  END LOOP;
  RETURN n;
END;
$$;
