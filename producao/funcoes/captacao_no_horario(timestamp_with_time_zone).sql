CREATE OR REPLACE FUNCTION public.captacao_no_horario(p_ts timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN dow <= 5
              THEN hm >= captacao_cfg('janela_inicio', '08:00') AND hm < captacao_cfg('janela_fim', '22:00')
              ELSE hm >= captacao_cfg('janela_inicio_fds', '08:00') AND hm < captacao_cfg('janela_fim_fds', '18:00')
         END
     AND NOT (hm >= captacao_cfg('pausa_inicio', '12:00') AND hm < captacao_cfg('pausa_fim', '13:30'))
  FROM (SELECT extract(isodow FROM p_ts AT TIME ZONE 'America/Manaus')::int AS dow,
               to_char(p_ts AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hm) t;
$function$;
