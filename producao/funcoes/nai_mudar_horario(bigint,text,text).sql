CREATE OR REPLACE FUNCTION public.nai_mudar_horario(p_turno bigint, p_codigo text, p_quando text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t   nai_turno;
  k   nai_contato;
  sel record;
  v   nai_visita;
  q   timestamptz := nai_ler_quando(p_quando);
  v_antes text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor muda o horario da visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'ele nao tem visita em andamento. se quer marcar, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Claro! De qual visita?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  IF q IS NULL THEN
    RETURN QUERY SELECT 'Certo! Pra qual dia e horário fica melhor?'::text, 'chame de novo com o horario no formato AAAA-MM-DD HH:MM.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro fica bom pro seu cliente?'::text, NULL::text; RETURN;
  END IF;

  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  v_antes := nai_quando_humano(v.quando);

  -- Horario novo em cima da hora (menos de 3h): mesma regra da visita urgente.
  IF q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 3)) THEN
    UPDATE nai_visita SET quando = q, estado = 'com_tel', aguardando = 'tel', urgente = true, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'urgente_com_tel', nai_hora_exata(q));
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, VISITA URGENTE (menos de ' || nai_cfg_int('antecedencia_minima_horas', 3) || 'h): o corretor ' ||
      coalesce(k.nome_completo, k.nome_whatsapp, '') || ' ' || nai_fone_fmt(k.telefone) || ' mudou a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) ||
      E'.\nEu parei aqui e parei de responder esse corretor. A visita é sua. Se quiser que eu siga, responda VISITA ' || v.id || ' OK.', 'urgente');
    PERFORM nai_parar_chat(k.id, 'visita #' || v.id || ': urgente (mudou o horario)');
    RETURN QUERY SELECT NULL::text, 'foi para o Tel (menos de 3h). responda exatamente SILENCIO.'::text;
    RETURN;
  END IF;

  -- O proprietario ja foi envolvido: pergunta de novo a ele, e o Fernando
  -- (se ja tinha confirmado) fica sabendo que mudou.
  IF v.moto_ok_em IS NOT NULL OR v.estado = 'aguardando_motoboy' THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' que era ' || nai_hora_exata(v.quando) ||
      ' vai mudar de horário. Te confirmo o novo assim que o proprietário responder.', 'motoboy_mudou', 600);
  END IF;
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, moto_ok_em = NULL, confirmada_em = NULL,
                        estado = CASE WHEN proprietario_id IS NULL THEN 'com_tel' ELSE 'aguardando_proprietario' END,
                        aguardando = CASE WHEN proprietario_id IS NULL THEN 'tel' ELSE 'proprietario' END,
                        reenvios_prop = 0, aviso_demora_em = NULL, aviso_tel_em = NULL,
                        lembrete_periodo_em = NULL, lembrete_1h_em = NULL, aviso_motoboy_em = NULL,
                        urgente = q < now() + make_interval(hours => nai_cfg_int('antecedencia_minima_horas', 2)),
                        atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'corretor_mudou_horario', v_antes || ' -> ' || nai_hora_exata(q));
  IF v.proprietario_id IS NULL THEN
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o corretor pediu para mudar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ') para ' || nai_hora_exata(q) || E'.\nResponda VISITA ' || v.id || ' OK quando o proprietário confirmar.', 'mudou_horario');
  ELSE
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'O corretor pediu para mudar a visita de ' || v_antes || ' para ' || nai_quando_humano(q) || '. Tem como receber nesse horário?',
      'mudou_horario', 500);
  END IF;
  RETURN QUERY SELECT 'Certo! Vou ver o novo horário com o proprietário e já te retorno.'::text,
    'NAO diga que o novo horario esta confirmado.'::text;
END;
$function$;
