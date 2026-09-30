CREATE OR REPLACE FUNCTION public.nay_devolver_aviso_de_saida(p_codigo text, p_erro text)
 RETURNS void
 LANGUAGE sql
AS $function$
  UPDATE aviso_de_saida SET avisado_em = NULL, erro = p_erro
   WHERE codigo = p_codigo;
$function$;
