CREATE OR REPLACE FUNCTION public.crm_visita_proprietario_ok(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v     nai_visita;
  v_msg text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF NOT nai_visita_aberta(v.estado) THEN
    RETURN QUERY SELECT false, 'Essa visita já está ' || v.estado || '.'; RETURN;
  END IF;
  UPDATE nai_visita SET prop_ok_em = coalesce(prop_ok_em, now()), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'proprietario_confirmou', 'marcado no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  v_msg := nai_visita_avisar_acompanhante(v.id, NULL, 'marcado no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  RETURN QUERY SELECT true, 'Proprietário confirmado: ' || coalesce(v_msg, 'o acompanhante não foi avisado') || '.';
END $function$;
