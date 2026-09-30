CREATE OR REPLACE FUNCTION public.nai_mascarar_texto(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT regexp_replace(coalesce(p_texto, ''), '(\d{4})\d{3,}(\d{2})', '\1***\2', 'g');
$function$
;
