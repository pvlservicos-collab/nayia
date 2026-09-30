CREATE OR REPLACE FUNCTION public.nai_trace_limpar(p_dias integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_dias int; v_ev int; v_cf int;
BEGIN
  v_dias := coalesce(p_dias, nai_cfg_int('trace_dias', 30));
  IF v_dias < 2 THEN v_dias := 2; END IF;  -- piso: nunca apagar o dia de hoje

  DELETE FROM nai_evento WHERE criado_em < now() - (v_dias || ' days')::interval;
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  -- A conferência é mais leve (não tem payload) e vale guardar mais tempo:
  -- é o histórico que mostra regra morta. 3x a retenção do evento.
  DELETE FROM nai_conferencia WHERE criado_em < now() - ((v_dias * 3) || ' days')::interval;
  GET DIAGNOSTICS v_cf = ROW_COUNT;

  RETURN jsonb_build_object('dias', v_dias, 'eventos_apagados', v_ev,
                            'conferencias_apagadas', v_cf);
END;
$function$;
