CREATE OR REPLACE FUNCTION public.nai_condominio_ok(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN coalesce(btrim(p), '') = '' OR p ~* 'identificado' THEN NULL ELSE btrim(p) END;
$function$
;
