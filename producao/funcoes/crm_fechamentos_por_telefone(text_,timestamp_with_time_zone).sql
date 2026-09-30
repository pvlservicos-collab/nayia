CREATE OR REPLACE FUNCTION public.crm_fechamentos_por_telefone(p_telefones text[], p_desde timestamp with time zone)
 RETURNS TABLE(telefone text, fechados integer, em_andamento integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT pe.telefone,
         (SELECT count(*)::int FROM nai_fechamento f
           WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NOT NULL AND f.concluido_em >= p_desde),
         (SELECT count(*)::int FROM nai_fechamento f
           WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL)
    FROM crm_pessoas(p_telefones) pe;
$function$;
