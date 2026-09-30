CREATE OR REPLACE FUNCTION public.crm_parceria_funil()
 RETURNS TABLE(telefone text, lid text, etapa text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT (SELECT nai_fone_br(c2.telefone) FROM nai_contato c2
           WHERE c2.id = ANY (nai_contato_irmaos(e.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
           ORDER BY c2.id LIMIT 1),
         (SELECT regexp_replace(c3.chave, '\D', '', 'g') FROM nai_contato c3
           WHERE c3.id = ANY (nai_contato_irmaos(e.contato_id)) AND c3.chave ~ '^lid:'
           ORDER BY c3.id LIMIT 1),
         CASE e.etapa WHEN 'identificacao' THEN 'Identificação'
                      WHEN 'recebeu_imovel' THEN 'Recebeu imóvel'
                      WHEN 'agendamento_visita' THEN 'Agendamento de visita' END
    FROM nai_etapa_contato e
   WHERE e.etapa IN ('identificacao', 'recebeu_imovel', 'agendamento_visita')
$function$;
