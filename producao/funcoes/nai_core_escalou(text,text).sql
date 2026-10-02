CREATE OR REPLACE FUNCTION public.nai_core_escalou(p_chave text, p_motivo text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint; n int;
BEGIN
  SELECT id INTO v_id FROM nai_contato WHERE chave = p_chave;
  IF v_id IS NULL THEN RETURN 0; END IF;
  UPDATE nai_contato
     SET humano_assumiu_em = now(),
         humano_motivo = 'duvida fora da base (nay-core): ' || left(coalesce(p_motivo, ''), 80)
   WHERE id = ANY (coalesce(nai_contato_irmaos(v_id), ARRAY[v_id]));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
