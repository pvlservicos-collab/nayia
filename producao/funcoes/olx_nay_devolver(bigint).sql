CREATE OR REPLACE FUNCTION public.olx_nay_devolver(p_chat bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ UPDATE privado.olx_chat_nay SET humano_em = NULL, humano_motivo = NULL, reservada_em = NULL, atualizado_em = now() WHERE chat = p_chat $function$;
