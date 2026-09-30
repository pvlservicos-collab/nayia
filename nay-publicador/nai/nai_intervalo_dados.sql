CREATE OR REPLACE FUNCTION public.nai_intervalo_dados(p_quando timestamp with time zone)
 RETURNS interval
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN p_quando - now() > interval '24 hours' THEN interval '60 minutes'
    WHEN p_quando - now() > interval '6 hours'  THEN interval '30 minutes'
    WHEN p_quando - now() > interval '2 hours'  THEN interval '10 minutes'
    ELSE interval '3 minutes' END;
$function$
;
