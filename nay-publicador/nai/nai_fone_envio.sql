CREATE OR REPLACE FUNCTION public.nai_fone_envio(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p ILIKE '%@lid' THEN regexp_replace(p, '\D', '', 'g') || '@lid'
    ELSE nai_fone_br(p)
  END;
$function$
;
