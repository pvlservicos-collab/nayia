CREATE OR REPLACE FUNCTION public.nai_tirar_anos(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT regexp_replace(lower(coalesce(p_texto, '')),
    '\m(em|de|desde|ano|feliz|que|para|pra)[ \t]+20[1-3][0-9]\M|\m20[1-3][0-9][ \t]+(seja|sera|será|foi|vai|chegou|chegando)\M',
    ' ', 'g');
$function$;
