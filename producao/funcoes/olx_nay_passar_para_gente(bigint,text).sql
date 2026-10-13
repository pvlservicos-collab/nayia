CREATE OR REPLACE FUNCTION public.olx_nay_passar_para_gente(p_chat bigint, p_motivo text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_chat_nay AS n (chat, humano_em, humano_motivo)
  VALUES (p_chat, now(), left(coalesce(p_motivo, ''), 300))
  ON CONFLICT (chat) DO UPDATE SET humano_em = now(), humano_motivo = excluded.humano_motivo, reservada_em = NULL, atualizado_em = now();
$function$;
