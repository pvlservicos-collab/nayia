CREATE OR REPLACE FUNCTION public.olx_imovel_vai_ao_cliente(p_codigo integer, p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM core_imovel_busca b WHERE b.codigo = p_codigo AND b.ofertavel)
      OR (EXISTS (SELECT 1 FROM imoveis i
                   WHERE i.codigo = p_codigo AND i.e_parceiro AND i.status = 'Disponível'
                     AND coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
                     AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0))
          AND olx_pode_receber_parceiro(p_telefone))
$function$;
