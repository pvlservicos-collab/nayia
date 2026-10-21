CREATE OR REPLACE FUNCTION public.cnm_norm(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT btrim(regexp_replace(lower(nay_sem_acento(coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g')) $function$;
