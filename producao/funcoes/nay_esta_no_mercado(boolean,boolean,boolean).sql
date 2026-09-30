CREATE OR REPLACE FUNCTION public.nay_esta_no_mercado(p_disponivel boolean, p_bloqueado boolean, p_no_site boolean)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_disponivel, true)
     AND NOT coalesce(p_bloqueado, false)
     AND coalesce(p_no_site, false)
$function$;
