CREATE OR REPLACE FUNCTION public.pergunta_fila_tick()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE f pergunta_fila; v_h int; v_saida bigint;
BEGIN
  IF NOT pergunta_fila_ligada() THEN RETURN 0; END IF;
  v_h := extract(hour FROM now() AT TIME ZONE 'America/Manaus')::int;
  IF v_h < nai_cfg_int('pergunta_fila_hora_ini', 7) OR v_h >= nai_cfg_int('pergunta_fila_hora_fim', 22) THEN RETURN 0; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'perguntada' LIMIT 1;
  IF f.id IS NOT NULL THEN
    IF coalesce(f.cobrada_em, f.perguntada_em)
       > now() - make_interval(mins => greatest(nai_cfg_int('pergunta_fila_cobrar_min', 10), 1)) THEN
      RETURN 0;
    END IF;
    v_saida := nai_avisar_tel(NULL, NULL, pergunta_fila_texto(f.id, true), 'pergunta_fila_cobranca');
    UPDATE pergunta_fila SET cobrada_em = now(), cobrancas = cobrancas + 1, saida_id = coalesce(v_saida, saida_id)
     WHERE id = f.id;
    RETURN 1;
  END IF;
  RETURN pergunta_fila_perguntar_proxima();
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pergunta_fila_tick: %', SQLERRM;
  RETURN 0;
END
$function$;
