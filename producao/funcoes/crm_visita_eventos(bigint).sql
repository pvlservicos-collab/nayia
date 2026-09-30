CREATE OR REPLACE FUNCTION public.crm_visita_eventos(p_visita bigint)
 RETURNS TABLE(quando timestamp with time zone, tipo text, detalhe text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  SELECT e.quando, e.tipo, e.detalhe FROM nai_visita_evento e WHERE e.visita_id = p_visita ORDER BY e.quando, e.id
$function$;
