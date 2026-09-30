CREATE OR REPLACE FUNCTION public.nay_reservar_lembretes(p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  UPDATE lembrete
     SET estado = 'enviado',
         tentativa = tentativa + 1,
         atualizado_em = now()
   WHERE id = ANY(p_ids) AND estado = 'agendado';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
