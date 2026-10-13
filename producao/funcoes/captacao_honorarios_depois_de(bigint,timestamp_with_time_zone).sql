CREATE OR REPLACE FUNCTION public.captacao_honorarios_depois_de(p_lead bigint, p_quando timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM privado.captacao_honorarios h WHERE h.lead_id = p_lead AND h.criado_em > p_quando);
$function$;
