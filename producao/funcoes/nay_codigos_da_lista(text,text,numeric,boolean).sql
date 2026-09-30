CREATE OR REPLACE FUNCTION public.nay_codigos_da_lista(p_categoria text, p_negocio text DEFAULT 'locacao'::text, p_valor_minimo numeric DEFAULT NULL::numeric, p_so_condominio boolean DEFAULT false)
 RETURNS TABLE(codigo text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT i.codigo::text
    FROM imoveis i
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND nay_categoria_do_imovel(i.tipo, i.condominio_nome) = p_categoria
     AND (CASE WHEN (lower(coalesce(p_negocio,'')) LIKE 'vend%'
                  OR lower(coalesce(p_negocio,'')) LIKE 'compr%')
               THEN coalesce(i.valor_venda,0)
               ELSE coalesce(i.valor_aluguel,0) END) > 0
     AND (p_valor_minimo IS NULL
          OR (CASE WHEN (lower(coalesce(p_negocio,'')) LIKE 'vend%'
                      OR lower(coalesce(p_negocio,'')) LIKE 'compr%')
                   THEN coalesce(i.valor_venda,0)
                   ELSE coalesce(i.valor_aluguel,0) END) >= p_valor_minimo)
     AND (NOT p_so_condominio
          OR nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL)
$function$;
