CREATE OR REPLACE FUNCTION public.zap_portal(p_origem text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_origem ~* 'viva' THEN 'Viva Real' WHEN p_origem ~* '^olx' THEN 'OLX' ELSE 'ZAP Imóveis' END
$function$;
