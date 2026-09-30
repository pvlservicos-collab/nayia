CREATE OR REPLACE FUNCTION public.nai_frase_maiuscula(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT upper(left(btrim(coalesce(p, '')), 1)) || substr(btrim(coalesce(p, '')), 2) ||
         CASE WHEN right(btrim(coalesce(p, '')), 1) IN ('.', '!', '?', '"') THEN '' ELSE '.' END;
$function$;
