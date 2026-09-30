CREATE OR REPLACE FUNCTION public.nai_visita_aberta(p_estado text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT p_estado NOT IN ('encerrada', 'cancelada', 'expirada');
$function$;
