CREATE OR REPLACE FUNCTION public.nai_cpf_fmt(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p ~ '^[0-9]{11}$'
    THEN substr(p,1,3) || '.' || substr(p,4,3) || '.' || substr(p,7,3) || '-' || substr(p,10,2)
    ELSE p END;
$function$
;
