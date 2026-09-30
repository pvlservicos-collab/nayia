CREATE OR REPLACE FUNCTION public.nai_cancelar_visita(p_turno bigint, p_codigo text, p_motivo text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; sel record; v nai_visita;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor cancela a visita dele.'::text; RETURN; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, NULL);
  IF sel.visita_id IS NULL THEN RETURN QUERY SELECT 'Não achei visita sua em andamento pra cancelar.'::text, NULL::text; RETURN; END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Qual delas?' || E'\n' || nai_lista_visitas_corretor(k.id))::text, 'pergunte qual e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  UPDATE nai_visita SET estado = 'cancelada', aguardando = NULL, motivo = left(p_motivo, 300), senha = NULL,
                        encerrada_em = now(), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'cancelada_pelo_corretor', p_motivo);
  IF v.proprietario_id IS NOT NULL AND v.ult_msg_prop_em IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
      'Passando para avisar que a visita de ' || nai_quando_humano(v.quando) || ' foi cancelada pelo corretor. Obrigada, e desculpa o transtorno.',
      'cancelada', 500);
  END IF;
  IF v.motoboy_id IS NOT NULL AND (v.ult_msg_moto_em IS NOT NULL OR v.moto_ok_em IS NOT NULL) THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.motoboy_id, 'motoboy',
      '' || nai_acompanhante() || ', a visita do ' || nai_ref_imovel(v.codigo) || ' de ' || nai_hora_exata(v.quando) || ' foi cancelada.', 'cancelada', 600);
  END IF;
  RETURN QUERY SELECT 'Tudo bem, cancelei a visita. Se quiser remarcar, é só me falar.'::text, NULL::text;
END;
$function$;
