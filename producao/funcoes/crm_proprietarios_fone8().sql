CREATE OR REPLACE FUNCTION public.crm_proprietarios_fone8()
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT right(regexp_replace(b.chave, '\D', '', 'g'), 8)
    FROM nay_proprietario_bloqueio b
   WHERE length(regexp_replace(b.chave, '\D', '', 'g')) >= 8
     -- o dono que também está procurando imóvel com a Nay Leads é lead: fica no pipeline
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp l
                      WHERE right(regexp_replace(l.telefone, '\D', '', 'g'), 8) = right(regexp_replace(b.chave, '\D', '', 'g'), 8))
$function$;
