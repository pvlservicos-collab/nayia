CREATE OR REPLACE FUNCTION public.crm_zap_ler(p_chave text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH u AS (UPDATE privado.zap_lead x SET lido_em = now() WHERE x.lido_em IS NULL AND zap_chave(x) = p_chave RETURNING 1)
  SELECT count(*)::integer FROM u
$function$;
