CREATE OR REPLACE FUNCTION public.nai_sem_emoji(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(coalesce(p, ''),
         '[🀀-🫿☀-➿️‍]', '', 'g'), '[ 	]{2,}', ' ', 'g'));
$function$;
