CREATE OR REPLACE FUNCTION public.nai_e_comando_envio(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM nai_ler_pedido_de_envio(p));
$function$;
