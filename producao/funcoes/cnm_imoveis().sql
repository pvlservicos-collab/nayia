CREATE OR REPLACE FUNCTION public.cnm_imoveis()
 RETURNS TABLE(codigo integer, ok boolean, falta jsonb, imovel jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT i.codigo, (m->>'ok')::boolean, m->'falta', m->'imovel'
    FROM imoveis i CROSS JOIN LATERAL cnm_imovel_montar(i.codigo) m
   WHERE i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
     AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false)
     AND (coalesce(i.valor_venda, 0) > 0 OR coalesce(i.valor_aluguel, 0) > 0)
   ORDER BY i.codigo
$function$;
