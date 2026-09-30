CREATE OR REPLACE FUNCTION public.nai_acompanhante_maiusculo()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT upper(nai_acompanhante());
$function$
;
