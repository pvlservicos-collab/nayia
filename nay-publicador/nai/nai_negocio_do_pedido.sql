CREATE OR REPLACE FUNCTION public.nai_negocio_do_pedido(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 146: "tem apartamento de 2 quartos?" virava aluguel de R$ 2. Valor de
  -- verdade comeca em R$ 300.
  SELECT coalesce(nai_negocio_da_conversa(p_contato, p_texto),
                  CASE WHEN x.v IS NULL OR x.v < 300 THEN NULL
                       WHEN x.v <= 30000 THEN 'locacao' WHEN x.v >= 100000 THEN 'venda' END)
    FROM (SELECT coalesce(nay_maior_valor(coalesce(p_texto, '')), nay_valor_em_reais(coalesce(p_texto, ''))) AS v) x;
$function$
;
