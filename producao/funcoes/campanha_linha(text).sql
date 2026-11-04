CREATE OR REPLACE FUNCTION public.campanha_linha(p_tel text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT CASE
    WHEN nay_leads_linha_do_dono(p_tel) = 'parceria' THEN 'parceria'
    WHEN EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_tel)
                    AND m.direcao = 'enviada' AND m.message_id LIKE 'wamid.%')
     AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_tel)
                        AND m.direcao = 'enviada' AND m.message_id IS NOT NULL AND m.message_id NOT LIKE 'wamid.%')
     AND NOT EXISTS (SELECT 1 FROM olx_lead_whatsapp o WHERE right(o.telefone, 8) = right(regexp_replace(p_tel, '\D', '', 'g'), 8))
    THEN 'oficial'
    ELSE 'captacao' END
$function$;
