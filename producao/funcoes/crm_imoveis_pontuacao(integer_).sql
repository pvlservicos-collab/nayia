CREATE OR REPLACE FUNCTION public.crm_imoveis_pontuacao(p_codigos integer[])
 RETURNS TABLE(codigo integer, pct integer, falta text[], falta_essencial text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT v.codigo, v.pct, v.falta, v.falta_essencial
    FROM vw_imovel_pontuacao v
   WHERE v.codigo = ANY (coalesce(p_codigos, '{}'::integer[]))
$function$;
