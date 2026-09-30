CREATE OR REPLACE FUNCTION public.nai_disparo_liberar(p_telefone text, p_codigo integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  DELETE FROM imovel_enviado_no_dia
   WHERE chave = nai_chave(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'))
     AND codigo = p_codigo AND origem = 'disparo'
     AND dia = (now() AT TIME ZONE 'America/Manaus')::date;
$function$;
