CREATE OR REPLACE FUNCTION public.nai_visita_corretor_confirmou(p_visita bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  v_apr   bigint := nai_aprovador_contato();
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
  dono    record;
  v_pede  text;
  v_res   text;
  v_dono  text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.estado <> 'confirmando' THEN RETURN; END IF;

  -- 179: o "sim" do corretor ja e a aprovacao
  IF nai_cfg('visita_sem_aprovacao', 'sim') = 'sim' THEN
    UPDATE nai_visita SET confirmada_corretor_em = now(), aprovada_em = now(),
                          aprovada_por = 'automática (o corretor confirmou)', atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'corretor_confirmou', nai_hora_exata(v.quando));
    PERFORM nai_evento(v.id, 'aprovada', 'automática');

    -- 197 (Pedro, 30/09/2026): a visita confirmada é da Rayssa (1ª solicitação ao
    -- proprietário, a confirmação completa à Rayssa, o Tel só avisado)
    IF nai_cfg('visita_com_a_rayssa', 'sim') = 'sim' THEN
      PERFORM nai_visita_para_a_rayssa(v.id, p_turno);
      RETURN;
    END IF;

    -- em cima da hora continua sendo do Tel (a mesma conferência do SIM)
    IF v.quando < now() + make_interval(hours => v_min_h) THEN
      UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
      PERFORM nai_avisar_tel(p_turno, v.id,
        nai_texto_visita_completa(v.id, 'Tel, o corretor confirmou mas a visita é em cima da hora (menos de ' || v_min_h
          || 'h) -- ela é sua. Parei o chat do corretor. Visita'),
        'visita_urgente');
      PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': em cima da hora');
      RETURN;
    END IF;

    -- sem telefone do proprietário, nai_pedir_ao_proprietario passa ao Tel e avisa
    v_res := nai_visita_seguir_para_proprietario(v.id, p_turno);
    IF v_res = 'com_tel' THEN RETURN; END IF;

    SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
    v_dono := coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '');
    PERFORM nai_avisar_tel(p_turno, v.id,
      nai_texto_visita_completa(v.id, 'Tel, o corretor confirmou e já estou falando com o proprietário' || v_dono
        || ' para fechar a visita'),
      'visita_com_proprietario');
    IF v_apr IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
        nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa')
          || ', só para você saber: o corretor confirmou e já estou falando com o proprietário' || v_dono
          || ' sobre a visita'),
        'visita_com_proprietario', 450);
    END IF;
    RETURN;
  END IF;

  -- 141 (visita_sem_aprovacao = 'nao'): pede o SIM ao aprovador
  UPDATE nai_visita SET estado = 'aguardando_rayssa', aguardando = 'equipe', confirmada_corretor_em = now(),
                        rayssa_msg_em = now(), rayssa_lembretes = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_confirmou', nai_hora_exata(v.quando));

  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  v_pede := CASE WHEN dono.motivo IS NULL
                 THEN 'Está tudo certo? Responda SIM ' || v.id || ' para eu falar com o proprietário, ou NÃO ' || v.id || '.'
                 ELSE 'Falta o telefone do proprietário. Me manda assim: TELEFONE ' || v.id
                      || ' [telefone …9999] -- e depois SIM ' || v.id || '. Ou NÃO ' || v.id || '.' END;
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
      nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa') || ', pedido de visita para confirmar')
      || E'\n\n' || v_pede, 'aprovar_visita', 450);
  END IF;
  PERFORM nai_avisar_tel(p_turno, v.id,
    nai_texto_visita_completa(v.id, 'Tel, novo pedido de visita (a ' || nai_cfg('aprovador_visita_nome', 'Rayssa') || ' vai confirmar)'),
    'visita_pedida');
END;
$function$;
