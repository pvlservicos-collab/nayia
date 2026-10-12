CREATE OR REPLACE FUNCTION public.nay_e_corretor_chave(p_chave text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(p_chave, '') <> '' AND (
       EXISTS (SELECT 1 FROM corretores c WHERE nay_fone_chave(nay_fone_com_ddi(c.telefone)) = p_chave)
    OR EXISTS (SELECT 1 FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
                 AND nay_fone_chave(nay_fone_com_ddi(p.telefone)) = p_chave))
$function$;
