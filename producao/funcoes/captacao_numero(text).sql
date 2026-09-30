CREATE OR REPLACE FUNCTION public.captacao_numero(p text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  m text[];
  n numeric;
BEGIN
  m := regexp_match(lower(coalesce(p, '')), '(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d+))?\s*(mil)?');
  IF m IS NULL THEN
    RETURN NULL;
  END IF;
  n := replace(m[1], '.', '')::numeric;
  IF m[2] IS NOT NULL THEN
    n := n + ('0.' || m[2])::numeric;
  END IF;
  IF m[3] = 'mil' THEN
    n := n * 1000;
  END IF;
  RETURN n;
END $function$;
