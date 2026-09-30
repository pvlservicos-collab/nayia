CREATE OR REPLACE FUNCTION public.nai_parada_e_para(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?(parar|pausar|parada)\s';
$function$
;
