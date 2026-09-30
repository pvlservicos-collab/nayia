CREATE OR REPLACE FUNCTION public.crm_contato_da_mensagem(p_message_id text)
 RETURNS TABLE(telefone text, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  (SELECT nai_fone_br(l.telefone), nullif(btrim(l.nome), '')
     FROM captacao_mensagens m JOIN captacao_leads l ON l.id = m.lead_id
    WHERE m.message_id = p_message_id AND coalesce(p_message_id, '') <> '' AND coalesce(l.telefone, '') <> ''
    LIMIT 1)
  UNION ALL
  (SELECT nai_fone_br(c.telefone), coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(c.nome_whatsapp), ''))
     FROM nai_saida s
     JOIN LATERAL (SELECT c2.* FROM nai_contato c2
                    WHERE c2.id = ANY (nai_contato_irmaos(s.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
                    ORDER BY c2.id LIMIT 1) c ON true
    WHERE s.message_id = p_message_id AND coalesce(p_message_id, '') <> ''
    LIMIT 1)
  LIMIT 1
$function$;
