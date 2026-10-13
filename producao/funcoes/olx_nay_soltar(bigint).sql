CREATE OR REPLACE FUNCTION public.olx_nay_soltar(p_chat bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ UPDATE privado.olx_chat_nay SET reservada_em = NULL, atualizado_em = now() WHERE chat = p_chat $function$;
