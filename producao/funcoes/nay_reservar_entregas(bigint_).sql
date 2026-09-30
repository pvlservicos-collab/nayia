CREATE OR REPLACE FUNCTION public.nay_reservar_entregas(p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  UPDATE entrega_pendente SET estado = 'entregue', entregue_em = now()
   WHERE id = ANY(p_ids) AND estado = 'devendo';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
