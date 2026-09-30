CREATE OR REPLACE FUNCTION public.nay_reservar_aviso_de_saida(p_codigo text)
 RETURNS boolean
 LANGUAGE sql
AS $function$
  WITH r AS (
    UPDATE aviso_de_saida SET avisado_em = now()
     WHERE codigo = p_codigo AND avisado_em IS NULL
     RETURNING codigo)
  SELECT count(*) > 0 FROM r;
$function$;
