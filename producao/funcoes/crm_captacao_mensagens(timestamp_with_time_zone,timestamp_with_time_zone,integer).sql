CREATE OR REPLACE FUNCTION public.crm_captacao_mensagens(p_desde timestamp with time zone, p_ate timestamp with time zone DEFAULT now(), p_limite integer DEFAULT 2000)
 RETURNS TABLE(id bigint, telefone text, nome text, direcao text, origem text, texto text, message_id text, criada_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT m.id, regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), nullif(btrim(l.nome), ''),
         m.direcao, coalesce(m.origem, ''), m.texto, nullif(m.message_id, ''), m.criada_em
    FROM captacao_mensagens m
    LEFT JOIN captacao_leads l ON l.id = m.lead_id
   WHERE m.criada_em >= p_desde AND m.criada_em < coalesce(p_ate, now())
     AND coalesce(m.telefone, '') !~ '-'                                   -- grupo não
     AND length(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 16
     -- 319: o número oficial já está na aba Oficial do CRM; aqui ele viraria conversa repetida na aba da Z-API
     AND NOT (coalesce(l.canal, 'zapi') = 'oficial' OR coalesce(m.message_id, '') LIKE 'wamid.%')
   ORDER BY m.criada_em, m.id
   LIMIT greatest(1, least(coalesce(p_limite, 2000), 5000))
$function$;
