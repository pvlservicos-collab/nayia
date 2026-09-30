CREATE OR REPLACE FUNCTION public.nai_quando_lembrete(p_ts timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE (p_ts AT TIME ZONE 'America/Manaus')::date - (now() AT TIME ZONE 'America/Manaus')::date
           WHEN 0 THEN 'hoje'
           WHEN 1 THEN 'amanhã (' || nai_dia_da_semana(p_ts) || ', ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'DD/MM') || ')'
           ELSE nai_dia_da_semana(p_ts) || ', ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'DD/MM') END
         || ' às ' || to_char(p_ts AT TIME ZONE 'America/Manaus', 'HH24"h"MI');
$function$;
