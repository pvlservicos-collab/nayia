CREATE OR REPLACE FUNCTION public.nay_liberar_imovel_do_dia(p_chave text, p_codigo integer)
 RETURNS void
 LANGUAGE sql
AS $function$
  DELETE FROM imovel_enviado_no_dia
   WHERE chave = p_chave
     AND codigo = p_codigo
     AND dia = (now() AT TIME ZONE 'America/Manaus')::date
     AND origem IN ('publicador', 'pendentes');
$function$;
