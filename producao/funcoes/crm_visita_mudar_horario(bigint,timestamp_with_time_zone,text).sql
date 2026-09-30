CREATE OR REPLACE FUNCTION public.crm_visita_mudar_horario(p_visita bigint, p_quando timestamp with time zone, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v nai_visita;
  v_lemb interval := make_interval(mins => nai_cfg_int('lembrete_corretor_min', 60));
  v_moto interval := make_interval(mins => nai_cfg_int('aviso_motoboy_min', 30));
  v_tel  interval := make_interval(hours => nai_cfg_int('aviso_tel_horas_antes', 2));
  fmt constant text := 'DD/MM HH24:MI';
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF v.estado IN ('realizada', 'encerrada', 'cancelada', 'expirada', 'coletando') THEN
    RETURN QUERY SELECT false, 'Essa visita já terminou (' || v.estado || '): o horário não muda mais.'; RETURN;
  END IF;
  IF p_quando IS NULL OR p_quando <= now() THEN
    RETURN QUERY SELECT false, 'Esse horário já passou.'; RETURN;
  END IF;
  IF p_quando > now() + interval '120 days' THEN
    RETURN QUERY SELECT false, 'Horário longe demais (mais de 4 meses).'; RETURN;
  END IF;
  IF p_quando = v.quando THEN
    RETURN QUERY SELECT true, 'O horário já era esse.'; RETURN;
  END IF;

  UPDATE nai_visita
     SET quando = p_quando,
         quando_sugerido = CASE WHEN quando_sugerido IS NOT DISTINCT FROM p_quando THEN NULL ELSE quando_sugerido END,
         -- cada lembrete volta a valer só se a hora dele ainda não passou
         lembrete_periodo_em = CASE WHEN nai_inicio_periodo(p_quando) > now() THEN NULL ELSE lembrete_periodo_em END,
         lembrete_1h_em      = CASE WHEN p_quando - v_lemb > now() THEN NULL ELSE lembrete_1h_em END,
         aviso_motoboy_em    = CASE WHEN p_quando - v_moto > now() THEN NULL ELSE aviso_motoboy_em END,
         aviso_tel_em        = CASE WHEN p_quando - v_tel  > now() THEN NULL ELSE aviso_tel_em END,
         atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'horario_mudado_no_crm',
    coalesce(to_char(v.quando AT TIME ZONE 'America/Manaus', fmt), '?') || ' → ' ||
    to_char(p_quando AT TIME ZONE 'America/Manaus', fmt) || ' (por ' || coalesce(nullif(btrim(p_quem), ''), 'CRM') || ')');
  RETURN QUERY SELECT true, 'Horário mudado para ' || to_char(p_quando AT TIME ZONE 'America/Manaus', fmt) || '. Ninguém foi avisado.';
END $function$;
