CREATE OR REPLACE FUNCTION public.pergunta_fila_perguntar_proxima()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE f pergunta_fila; v_h int; v_saida bigint;
BEGIN
  IF NOT pergunta_fila_ligada() OR EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'perguntada') THEN RETURN 0; END IF;
  v_h := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_h < nai_cfg_int('pergunta_fila_hora_ini', 7) OR v_h >= nai_cfg_int('pergunta_fila_hora_fim', 22) THEN RETURN 0; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'fila' ORDER BY ordem, id LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF f.id IS NULL THEN RETURN 0; END IF;
  UPDATE pergunta_fila SET estado = 'perguntada', perguntada_em = now(), cobrada_em = NULL WHERE id = f.id;
  v_saida := nai_avisar_tel(NULL, NULL, pergunta_fila_texto(f.id, false), 'pergunta_fila');
  UPDATE pergunta_fila SET saida_id = v_saida WHERE id = f.id;
  RETURN 1;
END
$function$;
