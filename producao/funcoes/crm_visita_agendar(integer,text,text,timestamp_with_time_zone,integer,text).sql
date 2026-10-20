CREATE OR REPLACE FUNCTION public.crm_visita_agendar(p_codigo integer, p_corretor_telefone text, p_corretor_nome text, p_quando timestamp with time zone, p_duracao_min integer, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text, visita bigint, corretor_telefone text, corretor_nome text, proprietario_telefone text, proprietario_nome text, imovel text, imovel_do_dono text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_aberta nai_visita;
  v_mudada bigint;
  v_mudou  boolean;
  v_msg    text;
  v_aviso  text := '';
  v_quem  text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_dur   int  := coalesce(p_duracao_min, 60);
  v_cor   bigint;
  v_prop  bigint;
  dono    record;
  c       nai_contato;
  v_id    bigint;
  v_registro boolean := false;   -- 450
  v_outra bigint;
  v_da_nay bigint;
  v_corte  timestamptz := nai_cfg('agenda_sem_visita_da_nay_desde', 'infinity')::timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN QUERY SELECT false, 'Não achei o imóvel ' || coalesce(p_codigo::text, '') || '.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  -- 450 (Pedro, 20/10): sem trava de horário. A visita de dia/hora que já passou é só registro (o lembrete não sai)
  IF p_quando IS NULL THEN
    RETURN QUERY SELECT false, 'Escolha o dia e a hora.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  IF v_dur < 15 OR v_dur > 480 THEN
    RETURN QUERY SELECT false, 'A duração tem que ficar entre 15 minutos e 8 horas.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  v_cor := nai_contato_do_cadastro(p_corretor_telefone, p_corretor_nome);
  IF v_cor IS NULL THEN
    RETURN QUERY SELECT false, 'Não entendi o telefone do corretor.', NULL::bigint, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;
  SELECT * INTO c FROM nai_contato WHERE id = v_cor;

  -- 312: o pedido que veio da Nay (fora da agenda) para este corretor e este imóvel
  -- vira ESTA visita, em vez de nascer outra
  SELECT v.id INTO v_da_nay FROM nai_visita v
   WHERE v.codigo = p_codigo AND v.corretor_id = v_cor AND v.estado = 'com_rayssa'
     AND v.criada_no_crm_por IS NULL AND v.excluida_em IS NULL AND v.criado_em >= v_corte
   ORDER BY v.id DESC LIMIT 1
     FOR UPDATE;

  -- a mesma visita duas vezes (clique duplo, ou duas pessoas agendando igual)
  SELECT v.id INTO v_outra FROM nai_visita v
   WHERE v.codigo = p_codigo AND v.corretor_id = v_cor AND v.quando = p_quando
     AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada') AND v.excluida_em IS NULL
     AND (v.criada_no_crm_por IS NOT NULL OR v.criado_em < v_corte)   -- a que a agenda não mostra não trava
   LIMIT 1;
  IF v_outra IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Essa visita já está na agenda (#' || v_outra || ').', v_outra, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text; RETURN;
  END IF;

  -- o dono, pelo cadastro (o mesmo caminho que a Nay usa para achar o proprietário)
  SELECT * INTO dono FROM nai_proprietario_do_imovel(p_codigo);
  IF dono.motivo IS NULL AND dono.telefone IS NOT NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
    IF v_prop = v_cor THEN v_prop := NULL; END IF;
  END IF;

  -- 330: o índice nai_visita_uma_aberta deixa UMA visita aberta por corretor e imóvel. A que ficou aberta de um
  -- dia que já passou (ninguém marcou realizada) é encerrada; a que ainda vai acontecer muda para o horário novo.
  IF v_da_nay IS NULL THEN
    SELECT * INTO v_aberta FROM nai_visita v
     WHERE v.codigo = p_codigo AND v.corretor_id = v_cor
       AND v.estado NOT IN ('realizada', 'encerrada', 'cancelada', 'expirada')
     ORDER BY v.id DESC LIMIT 1
       FOR UPDATE;
    IF v_aberta.id IS NOT NULL AND (v_aberta.quando IS NULL OR v_aberta.quando < now()) THEN
      UPDATE nai_visita x
         SET estado = 'encerrada', aguardando = NULL, senha = NULL,
             encerrada_em = coalesce(x.encerrada_em, now()),
             motivo = coalesce(x.motivo, left('Ficou aberta; ' || v_quem || ' agendou outra no CRM', 200)),
             atualizado_em = now()
       WHERE x.id = v_aberta.id;
      UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = 'visita encerrada: outra agendada no CRM'
       WHERE s.visita_id = v_aberta.id AND s.estado = 'pendente';
      PERFORM nai_evento(v_aberta.id, 'encerrada_por_outra',
        left(v_quem || ' agendou outra visita do mesmo corretor ao mesmo imóvel', 200));
      v_aviso := ' A de ' || coalesce(to_char(v_aberta.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), 'antes')
                 || ' (#' || v_aberta.id || '), que tinha ficado aberta, foi encerrada.';
    ELSIF v_aberta.id IS NOT NULL AND p_quando < now() THEN
      -- 450: registro de uma visita que já passou, com outra deste corretor a este imóvel ainda por acontecer: a aberta
      -- fica como está e o registro nasce encerrado (o índice nai_visita_uma_aberta deixa só uma aberta)
      v_registro := true;
    ELSIF v_aberta.id IS NOT NULL THEN
      SELECT m.ok, m.mensagem INTO v_mudou, v_msg FROM crm_visita_mudar_horario(v_aberta.id, p_quando, v_quem) m;
      IF NOT coalesce(v_mudou, false) THEN
        RETURN QUERY SELECT false,
          coalesce(v_msg, 'Não consegui mudar a visita #' || v_aberta.id || '.') || ' (já existe a visita #' || v_aberta.id
            || ' deste corretor a este imóvel)',
          v_aberta.id, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text;
        RETURN;
      END IF;
      UPDATE nai_visita x
         SET duracao_min = v_dur, criada_no_crm_por = coalesce(x.criada_no_crm_por, v_quem), atualizado_em = now()
       WHERE x.id = v_aberta.id;
      v_mudada := v_aberta.id;
      v_aviso := ' Já havia a visita #' || v_aberta.id || ' deste corretor a este imóvel ('
                 || to_char(v_aberta.quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || '): ela passou para o horário novo.';
    END IF;
  END IF;

  IF v_mudada IS NOT NULL THEN
    v_id := v_mudada;
  ELSIF v_da_nay IS NOT NULL THEN
    -- (com o apelido `v`: proprietario_nome também é coluna de SAÍDA desta função)
    UPDATE nai_visita v
       SET quando = p_quando, duracao_min = v_dur, criada_no_crm_por = v_quem,
           proprietario_id = coalesce(v.proprietario_id, v_prop),
           proprietario_cadastro = coalesce(v.proprietario_cadastro, dono.cadastro_id),
           proprietario_nome = coalesce(v.proprietario_nome, dono.nome),
           aprovada_em = now(), aprovada_por = left('CRM: ' || v_quem, 120), atualizado_em = now()
     WHERE v.id = v_da_nay;
    v_id := v_da_nay;
    PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' pôs na agenda o pedido que veio pela Nay, ' || v_dur || ' min', 200));
  ELSE
  INSERT INTO nai_visita (codigo, corretor_id, proprietario_id, proprietario_cadastro, proprietario_nome,
                          quando, estado, aguardando, duracao_min, criada_no_crm_por,
                          confirmada_corretor_em, aprovada_em, aprovada_por)
  VALUES (p_codigo, v_cor, v_prop, dono.cadastro_id, dono.nome,
          p_quando, CASE WHEN v_registro THEN 'encerrada' ELSE 'com_rayssa' END,
          CASE WHEN v_registro THEN NULL ELSE 'equipe' END, v_dur, v_quem,
          now(), now(), left('CRM: ' || v_quem, 120))
  RETURNING id INTO v_id;
  IF v_registro THEN
    UPDATE nai_visita SET encerrada_em = now(), motivo = 'Registro no CRM de uma visita que já passou' WHERE id = v_id;
  END IF;
  PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' agendou à mão, ' || v_dur || ' min', 200));
  END IF;

  RETURN QUERY SELECT true,
    'Visita #' || v_id || ' agendada para ' || nai_hora_exata(p_quando) || '.' || v_aviso,
    v_id, c.telefone, coalesce(c.nome_completo, c.nome_whatsapp),
    CASE WHEN dono.motivo IS NULL THEN dono.telefone END, dono.nome,
    nai_ref_imovel(p_codigo), nai_ref_imovel_prop(p_codigo);
END $function$;
