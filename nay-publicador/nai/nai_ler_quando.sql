CREATE OR REPLACE FUNCTION public.nai_ler_quando(p text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE m text[];
BEGIN
  m := regexp_match(coalesce(p, ''), '(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})');
  IF m IS NULL THEN RETURN NULL; END IF;
  RETURN make_timestamptz(m[1]::int, m[2]::int, m[3]::int, m[4]::int, m[5]::int, 0, 'America/Manaus');
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$function$
;
