CREATE OR REPLACE FUNCTION public.nai_tirar_frase(p_texto text, p_regex text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(coalesce(p_texto, ''), '[^.?!' || chr(10) || ']*(' || p_regex || ')[^.?!' || chr(10) || ']*[.?!]?', '', 'gi'));
$function$
;
