CREATE OR REPLACE FUNCTION public.nai_saudacao(p_ts timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN h >= 6 AND h < 12 THEN 'Bom dia'
    WHEN h >= 12 AND h < 18 THEN 'Boa tarde'
    ELSE 'Boa noite' END
  FROM (SELECT extract(hour FROM p_ts AT TIME ZONE 'America/Manaus')::int AS h) t;
$function$
;
