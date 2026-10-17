CREATE OR REPLACE FUNCTION public.crm_donos_do_cadastro(p_fins text[])
 RETURNS TABLE(fim8 text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT DISTINCT right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8)
    FROM proprietarios p
   WHERE right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 8) = ANY (coalesce(p_fins, '{}'))
$function$;
