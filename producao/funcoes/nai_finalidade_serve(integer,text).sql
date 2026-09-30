CREATE OR REPLACE FUNCTION public.nai_finalidade_serve(p_codigo integer, p_negocio text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- Conversa sem negócio definido, ou 'ambos': não barra (quem pergunta
  -- "alugar ou comprar?" é a busca). Imóvel sem preço: não barra.
  SELECT CASE WHEN p_negocio IS NULL OR p_negocio NOT IN ('locacao', 'venda') THEN true
              ELSE coalesce(nai_finalidade_do_imovel(p_codigo) IN (p_negocio, 'ambos'), true) END;
$function$;
