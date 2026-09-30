CREATE OR REPLACE FUNCTION public.nay_congelar_lembretes(p_telefone text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  UPDATE lembrete
     SET estado = 'congelado', atualizado_em = now()
   WHERE telefone = p_telefone
     AND estado IN ('agendado','enviado');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
