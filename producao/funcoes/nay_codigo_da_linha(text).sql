CREATE OR REPLACE FUNCTION public.nay_codigo_da_linha(p_linha text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT (regexp_match(coalesce(p_linha,''),
                       '\mc[óo]d(?:igo)?\.?\s*:?\s*([0-9]{2,5})\M', 'i'))[1];
$function$;
