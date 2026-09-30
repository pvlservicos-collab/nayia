CREATE OR REPLACE FUNCTION public.nai_finalidade_do_imovel(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- A mesma régua de `nai_oferta_serve`: aluguel > 0 é locação, venda > 0 é
  -- venda, os dois é 'ambos'. Sem preço nenhum: NULL (não se sabe).
  SELECT CASE WHEN a AND v THEN 'ambos' WHEN a THEN 'locacao' WHEN v THEN 'venda' END
    FROM (SELECT coalesce(i.valor_aluguel, 0) > 0 AS a, coalesce(i.valor_venda, 0) > 0 AS v
            FROM imoveis i WHERE i.codigo = p_codigo) x;
$function$;
