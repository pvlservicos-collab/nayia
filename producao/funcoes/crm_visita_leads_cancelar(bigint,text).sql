CREATE OR REPLACE FUNCTION public.crm_visita_leads_cancelar(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v privado.olx_visita;
BEGIN
  SELECT * INTO v FROM privado.olx_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita da Nay Leads.'; RETURN;
  END IF;
  IF v.estado IN ('cancelada', 'expirada') THEN
    RETURN QUERY SELECT true, 'Essa visita já não estava valendo.'; RETURN;
  END IF;
  IF v.estado = 'realizada' THEN
    RETURN QUERY SELECT false, 'Essa visita já foi marcada como realizada' || coalesce(' por ' || v.realizada_por, '') || '.'; RETURN;
  END IF;
  UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now() WHERE id = v.id;
  UPDATE privado.olx_visita_consulta SET estado = 'cancelada' WHERE visita = v.id AND estado = 'esperando';
  RETURN QUERY SELECT true, 'Visita cancelada' || coalesce(' por ' || nullif(btrim(p_quem), ''), '') || '. Ninguém foi avisado.';
END $function$;
