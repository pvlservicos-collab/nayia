CREATE OR REPLACE FUNCTION public.nay_custo_cheio(p_codigo text, p_negocio text DEFAULT 'locacao'::text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN p_negocio = 'venda' THEN i.valor_venda
    WHEN coalesce(i.extras->>'incluso no aluguel','') ILIKE '%condom%'
      THEN i.valor_aluguel
    ELSE coalesce(i.valor_aluguel,0) + coalesce(i.taxa_condominio,0)
  END
  FROM imoveis i WHERE i.codigo::text = p_codigo;
$function$;
