CREATE OR REPLACE FUNCTION public.nai_visita_com_a_rayssa(p_estado text, p_quando timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- a visita é da Rayssa até o horário dela + visita_rayssa_ate_min (ou até fechar)
  SELECT p_estado = 'com_rayssa'
     AND (p_quando IS NULL OR p_quando + make_interval(mins => nai_cfg_int('visita_rayssa_ate_min', 120)) > now());
$function$;
