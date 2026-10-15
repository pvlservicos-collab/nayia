CREATE OR REPLACE FUNCTION public.olx_nay_devolver(p_chat bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_chat_nay AS n (chat, devolvida_em) VALUES (p_chat, now())
  ON CONFLICT (chat) DO UPDATE
     SET humano_em = NULL, humano_motivo = NULL, reservada_em = NULL, devolvida_em = now(), atualizado_em = now();
$function$;
