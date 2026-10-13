CREATE OR REPLACE FUNCTION public.olx_cfg(p_chave text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ SELECT c.valor FROM privado.olx_config c WHERE c.chave = p_chave $function$;
