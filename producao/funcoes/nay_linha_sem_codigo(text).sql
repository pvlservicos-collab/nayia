CREATE OR REPLACE FUNCTION public.nay_linha_sem_codigo(p_linha text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(
           regexp_replace(coalesce(p_linha,''),
                          '\mc[óo]d(?:igo)?\.?\s*:?\s*[0-9]{2,5}\M', ' ', 'gi'),
           '\s+', ' ', 'g'));
$function$;
