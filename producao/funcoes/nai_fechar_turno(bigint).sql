CREATE OR REPLACE FUNCTION public.nai_fechar_turno(p_turno bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_ids bigint[];
BEGIN
  UPDATE nai_turno SET fechado_em = coalesce(fechado_em, now()) WHERE id = p_turno RETURNING msg_ids INTO v_ids;
  UPDATE mensagens SET status = 'Respondido' WHERE id = ANY (coalesce(v_ids, '{}')) AND status = 'Processando';
  RETURN p_turno;
END;
$function$;
