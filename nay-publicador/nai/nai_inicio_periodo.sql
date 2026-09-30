CREATE OR REPLACE FUNCTION public.nai_inicio_periodo(p_quando timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
AS $function$
  SELECT ((l::date + nai_cfg(CASE WHEN extract(hour FROM l) < 12 THEN 'inicio_manha'
                                  WHEN extract(hour FROM l) < 18 THEN 'inicio_tarde'
                                  ELSE 'inicio_noite' END, '08:00')::time) AT TIME ZONE 'America/Manaus')
    FROM (SELECT p_quando AT TIME ZONE 'America/Manaus' AS l) t;
$function$
;
