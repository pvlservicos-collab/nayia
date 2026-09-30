CREATE OR REPLACE FUNCTION public.nai_hora_exata(p_ts timestamp with time zone)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT (ARRAY['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow FROM l)::int + 1]
         || ' ' || to_char(l, 'DD/MM') || ' às ' || to_char(l, 'HH24:MI')
    FROM (SELECT p_ts AT TIME ZONE 'America/Manaus' AS l) t;
$function$;
