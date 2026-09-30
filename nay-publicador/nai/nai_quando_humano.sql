CREATE OR REPLACE FUNCTION public.nai_quando_humano(p_ts timestamp with time zone, p_agora timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  l    timestamp := p_ts AT TIME ZONE 'America/Manaus';
  hoje date := (p_agora AT TIME ZONE 'America/Manaus')::date;
  d    int;
  h    int;
  mi   int;
  dia  text;
  per  text;
  hora text;
  sem  text[] := ARRAY['domingo','segunda-feira','terça-feira','quarta-feira','quinta-feira','sexta-feira','sábado'];
BEGIN
  IF p_ts IS NULL THEN RETURN NULL; END IF;
  d  := l::date - hoje;
  h  := extract(hour FROM l)::int;
  mi := extract(minute FROM l)::int;
  dia := CASE
    WHEN d = 0 THEN 'hoje'
    WHEN d = 1 THEN 'amanhã'
    WHEN d = -1 THEN 'ontem'
    WHEN d BETWEEN 2 AND 6 THEN sem[extract(dow FROM l)::int + 1]
    ELSE sem[extract(dow FROM l)::int + 1] || ', dia ' || extract(day FROM l)::int
  END;
  IF h = 12 AND mi = 0 THEN
    RETURN dia || ', ao meio-dia';
  END IF;
  per  := CASE WHEN h < 12 THEN 'de manhã' WHEN h < 18 THEN 'à tarde' ELSE 'à noite' END;
  hora := 'às ' || h || 'h' || CASE WHEN mi > 0 THEN lpad(mi::text, 2, '0') ELSE '' END;
  IF d >= 7 THEN
    RETURN dia || ', ' || per || ', ' || hora;
  END IF;
  RETURN dia || ' ' || per || ', ' || hora;
END;
$function$
;
