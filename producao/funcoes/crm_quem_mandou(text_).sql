CREATE OR REPLACE FUNCTION public.crm_quem_mandou(p_ids text[])
 RETURNS TABLE(message_id text, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT x.id,
         CASE
           WHEN EXISTS (SELECT 1 FROM core_saida s WHERE s.message_id = x.id)
             OR EXISTS (SELECT 1 FROM nai_saida s WHERE s.message_id = x.id)
             OR EXISTS (SELECT 1 FROM mensagem_saida s WHERE s.message_id = x.id) THEN 'nay'
           WHEN EXISTS (SELECT 1 FROM envios e WHERE e.message_id = x.id)
             OR EXISTS (SELECT 1 FROM envios_foto f WHERE f.message_id = x.id)
             OR EXISTS (SELECT 1 FROM saida_do_sistema o WHERE o.message_id = x.id) THEN 'sistema'
           ELSE 'gente'
         END
    FROM (SELECT DISTINCT u.id FROM unnest(p_ids) AS u(id) WHERE nullif(btrim(u.id), '') IS NOT NULL) x
   LIMIT 1000
$function$;
