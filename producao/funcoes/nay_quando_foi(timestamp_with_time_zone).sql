CREATE OR REPLACE FUNCTION public.nay_quando_foi(p_em timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE (p_em AT TIME ZONE 'America/Manaus')::date
              - (now() AT TIME ZONE 'America/Manaus')::date
              WHEN 0  THEN 'hoje'
              WHEN -1 THEN 'ontem'
              WHEN 1  THEN 'amanhã'
              ELSE 'em ' || to_char(p_em AT TIME ZONE 'America/Manaus', 'DD/MM') END
         || ' às ' || to_char(p_em AT TIME ZONE 'America/Manaus', 'HH24"h"MI');
$function$;
