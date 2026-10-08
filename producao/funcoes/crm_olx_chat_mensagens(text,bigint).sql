CREATE OR REPLACE FUNCTION public.crm_olx_chat_mensagens(p_conta text, p_chat bigint)
 RETURNS TABLE(id bigint, message_id text, de text, texto text, quando timestamp with time zone, enviada_por text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.id, m.message_id, m.de, m.texto, m.quando, m.enviada_por
    FROM privado.olx_chat_mensagem m JOIN privado.olx_chat h ON h.id = m.chat
   WHERE h.conta = p_conta AND h.id = p_chat
   ORDER BY m.id
   LIMIT 2000
$function$;
