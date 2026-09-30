CREATE OR REPLACE FUNCTION public.nai_ler_hora_tel(p text, p_base timestamp with time zone)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  m  text[];
  d  date := (coalesce(p_base, now()) AT TIME ZONE 'America/Manaus')::date;
  h  int; mi int;
BEGIN
  m := regexp_match(p, '(\d{1,2})/(\d{1,2})');
  IF m IS NOT NULL THEN
    d := make_date(extract(year FROM now() AT TIME ZONE 'America/Manaus')::int, m[2]::int, m[1]::int);
  END IF;
  m := regexp_match(p, '(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?!\d|/)');
  IF m IS NULL THEN RETURN NULL; END IF;
  h := m[1]::int; mi := coalesce(m[2], '0')::int;
  IF h > 23 OR mi > 59 THEN RETURN NULL; END IF;
  -- Sem data e a hora de hoje ja passou: e amanha. O Tel responde "VISITA 12
  -- AVISA 10h" as 23h querendo dizer amanha as 10h -- antes voltava "nao entendi".
  IF regexp_match(p, '(\d{1,2})/(\d{1,2})') IS NULL
     AND make_timestamptz(extract(year FROM d)::int, extract(month FROM d)::int, extract(day FROM d)::int, h, mi, 0, 'America/Manaus') <= now() THEN
    d := d + 1;
  END IF;
  RETURN make_timestamptz(extract(year FROM d)::int, extract(month FROM d)::int, extract(day FROM d)::int, h, mi, 0, 'America/Manaus');
EXCEPTION WHEN others THEN RETURN NULL;
END;
$function$;
