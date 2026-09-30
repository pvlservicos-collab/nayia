CREATE OR REPLACE FUNCTION public.nai_palavra_conhecida(p text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM nai_palavra_conhecida
                  WHERE palavra = lower(unaccent(regexp_replace(coalesce(p, ''), '[^[:alnum:]]', '', 'g'))));
$function$
;
