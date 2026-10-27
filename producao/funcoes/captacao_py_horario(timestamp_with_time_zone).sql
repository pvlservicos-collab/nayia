CREATE OR REPLACE FUNCTION public.captacao_py_horario(p_ts timestamp with time zone DEFAULT now())
 RETURNS TABLE(n integer, hora text, inicio timestamp with time zone, total integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH h AS (
    SELECT x.hora, x.n::int AS n, count(*) OVER ()::int AS total
      FROM unnest(string_to_array(regexp_replace(captacao_cfg('python_horarios', ''), '\s', '', 'g'), ',')) WITH ORDINALITY AS x(hora, n)
     WHERE x.hora ~ '^\d{1,2}:\d{2}$'
  )
  SELECT h.n, h.hora, (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time) AT TIME ZONE 'America/Manaus', h.total
    FROM h
   WHERE p_ts >= (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time) AT TIME ZONE 'America/Manaus'
     AND p_ts <  (date_trunc('day', p_ts AT TIME ZONE 'America/Manaus') + h.hora::time
                  + make_interval(mins => captacao_cfg('python_horario_duracao_min', '120')::int)) AT TIME ZONE 'America/Manaus'
   ORDER BY h.n
   LIMIT 1;
$function$;
