CREATE OR REPLACE FUNCTION public.crm_campanha_cancelar(p_ids bigint[], p_motivo text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_n int;
BEGIN
  WITH c AS (
    UPDATE campanha_contato SET estado = 'cancelada', atualizado_em = now(),
           erro = left(coalesce(nullif(btrim(p_motivo), ''), 'cancelada') || coalesce(' (' || nullif(btrim(p_quem), '') || ')', ''), 300)
     WHERE id = ANY (p_ids) AND estado IN ('preparada', 'liberada') RETURNING id, erro
  ), ev AS (INSERT INTO campanha_evento (contato, tipo, texto) SELECT id, 'cancelada', erro FROM c RETURNING 1)
  SELECT count(*) INTO v_n FROM ev;
  RETURN v_n;
END;
$function$;
