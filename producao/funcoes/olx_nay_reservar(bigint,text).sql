CREATE OR REPLACE FUNCTION public.olx_nay_reservar(p_chat bigint, p_quem text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_ok boolean := false;
BEGIN
  INSERT INTO privado.olx_chat_nay AS n (chat, reservada_em, reservada_por)
  VALUES (p_chat, now(), left(coalesce(p_quem, 'nay-olx'), 60))
  ON CONFLICT (chat) DO UPDATE SET reservada_em = now(), reservada_por = excluded.reservada_por, atualizado_em = now()
   WHERE n.humano_em IS NULL AND (n.reservada_em IS NULL OR n.reservada_em < now() - interval '5 minutes')
  RETURNING true INTO v_ok;
  RETURN coalesce(v_ok, false);
END $function$;
