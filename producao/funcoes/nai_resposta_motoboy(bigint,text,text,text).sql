CREATE OR REPLACE FUNCTION public.nai_resposta_motoboy(p_turno bigint, p_visita text, p_decisao text, p_obs text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t   nai_turno;
  v   nai_visita;
  dec text := lower(coalesce(p_decisao, ''));
  v_id bigint := coalesce(NULLIF(regexp_replace(coalesce(p_visita, ''), '\D', '', 'g'), '')::bigint, NULL);
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'motoboy' THEN
    RETURN QUERY SELECT NULL::text, 'so para quando quem escreve e o ' || nai_acompanhante() || '.'::text; RETURN;
  END IF;
  -- A visita: a do cabecalho; senao, a que ele citou -- mas SO se for dele.
  SELECT * INTO v FROM nai_visita x
   WHERE x.id = coalesce(t.visita_id, v_id)
     AND nai_visita_aberta(x.estado)
     AND (x.motoboy_id = t.contato_id OR t.teste);
  IF v.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao sei de qual visita ele fala. mostre a lista do contexto e pergunte qual (pelo numero da visita).'::text; RETURN;
  END IF;

  IF dec IN ('confirma', 'sim', 'ok') THEN
    UPDATE nai_visita SET moto_ok_em = now(), atualizado_em = now() WHERE id = v.id RETURNING * INTO v;
    PERFORM nai_evento(v.id, 'motoboy_ok', p_obs);
    IF v.prop_ok_em IS NOT NULL AND v.estado = 'aguardando_motoboy' THEN
      PERFORM nai_confirmar_visita(v.id, p_turno);
    END IF;
    RETURN QUERY SELECT nai_texto_motoboy_ok(v), 'diga o texto_pronto como veio.'::text; RETURN;
  END IF;

  IF dec IN ('nao_pode', 'nao', 'problema', 'imprevisto') THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', moto_ok_em = NULL, atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'motoboy_nao_pode', p_obs);
    PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o ' || nai_acompanhante() || ' disse que NÃO consegue acompanhar a visita #' || v.id || ' (' ||
      nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || ')' || coalesce(': "' || left(p_obs, 300) || '"', '') ||
      E'.\nNão existe acompanhante reserva. Parei com o ' || nai_acompanhante() || ' e com o corretor até você responder.\nMe responda VISITA ' || v.id || ' HORARIO <novo> ou VISITA ' || v.id || ' CANCELA.',
      'motoboy_nao_pode');
    PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': ' || nai_acompanhante() || ' nao pode');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': ' || nai_acompanhante() || ' nao pode');
    -- CALADA (Tel, 12/09): foi para o Tel, o corretor nao e avisado.
    RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text; RETURN;
  END IF;

  PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, o ' || nai_acompanhante() || ' escreveu sobre a visita #' || v.id || ': "' ||
    left(coalesce(nullif(p_obs, ''), t.texto, ''), 300) || E'"\nParei de responder o ' || nai_acompanhante() || ' até você mandar um VISITA ' || v.id || ' ...', 'motoboy_outro');
  PERFORM nai_parar_chat(t.contato_id, 'visita #' || v.id || ': mensagem do ' || nai_acompanhante() || '');
  RETURN QUERY SELECT NULL::text,
      'ja avisei o Tel. A pessoa NAO fica sabendo (regra do Tel, 12/09): responda exatamente SILENCIO.'::text;
END;
$function$;
