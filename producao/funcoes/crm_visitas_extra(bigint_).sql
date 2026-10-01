CREATE OR REPLACE FUNCTION public.crm_visitas_extra(p_ids bigint[])
 RETURNS TABLE(id bigint, duracao_min integer, criada_no_crm_por text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT v.id, v.duracao_min, v.criada_no_crm_por
    FROM nai_visita v
   WHERE v.id = ANY (coalesce(p_ids, '{}'::bigint[]))
     AND (v.duracao_min IS NOT NULL OR v.criada_no_crm_por IS NOT NULL)
$function$;
