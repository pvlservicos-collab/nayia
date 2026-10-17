CREATE OR REPLACE FUNCTION public.olx_pode_receber_parceiro(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- cliente final: tem telefone e não é corretor (dos grupos ou parceiro do site antigo)
  SELECT length(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')) >= 10
     AND NOT coalesce(nay_e_corretor_chave(nay_fone_chave(nay_fone_com_ddi(regexp_replace(p_telefone, '\D', '', 'g')))), false)
$function$;
