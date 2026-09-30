CREATE OR REPLACE FUNCTION public.crm_etapa_da_nay(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM nai_fechamento f WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL) THEN 'fechamento'
    ELSE (SELECT m.etapa FROM nai_etapa_manual m
           WHERE m.contato_id = ANY (pe.ids) AND (m.valido_ate IS NULL OR m.valido_ate > now())
             AND m.etapa IN ('visitas', 'proprietarios', 'fechamento')
           ORDER BY m.definido_em DESC LIMIT 1)
  END
    FROM crm_pessoas(ARRAY[p_telefone]) pe
   LIMIT 1;
$function$;
