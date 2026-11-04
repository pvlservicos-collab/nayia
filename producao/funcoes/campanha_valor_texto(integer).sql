CREATE OR REPLACE FUNCTION public.campanha_valor_texto(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN coalesce(valor_venda, 0) > 0 AND coalesce(valor_aluguel, 0) > 0
                THEN campanha_dinheiro(valor_venda) || ' na venda e ' || campanha_dinheiro(valor_aluguel) || ' por mês no aluguel'
              WHEN coalesce(valor_aluguel, 0) > 0 THEN campanha_dinheiro(valor_aluguel) || ' por mês'
              ELSE campanha_dinheiro(valor_venda) END
    FROM imoveis WHERE codigo = p_codigo
$function$;
