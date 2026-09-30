CREATE OR REPLACE FUNCTION public.nay_devolver_respostas(p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  UPDATE resposta_a_entregar SET estado = 'devendo', entregue_em = NULL
   WHERE id = ANY(p_ids) AND estado = 'entregue';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
