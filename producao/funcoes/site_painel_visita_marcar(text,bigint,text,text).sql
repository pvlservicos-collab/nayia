CREATE OR REPLACE FUNCTION public.site_painel_visita_marcar(p_origem text, p_id bigint, p_resultado text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_res text := nullif(lower(btrim(coalesce(p_resultado, ''))), '');
BEGIN
  IF p_origem NOT IN ('parceria', 'olx') THEN RETURN jsonb_build_object('ok', false, 'erro', 'origem inválida'); END IF;
  IF p_origem = 'parceria' AND NOT EXISTS (SELECT 1 FROM nai_visita WHERE id = p_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'visita não encontrada');
  END IF;
  IF p_origem = 'olx' AND NOT EXISTS (SELECT 1 FROM privado.olx_visita WHERE id = p_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'visita não encontrada');
  END IF;
  IF v_res IS NULL THEN
    DELETE FROM privado.visita_resultado WHERE origem = p_origem AND visita_id = p_id;
    RETURN jsonb_build_object('ok', true, 'resultado', NULL);
  END IF;
  IF v_res NOT IN ('desistiu', 'realizada', 'fechou') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'resultado é desistiu, realizada ou fechou');
  END IF;
  INSERT INTO privado.visita_resultado (origem, visita_id, resultado, marcado_por, marcado_em)
  VALUES (p_origem, p_id, v_res, left(coalesce(p_quem, ''), 80), now())
  ON CONFLICT (origem, visita_id) DO UPDATE SET resultado = EXCLUDED.resultado, marcado_por = EXCLUDED.marcado_por,
                                                marcado_em = now();
  RETURN jsonb_build_object('ok', true, 'resultado', v_res);
END
$function$;
