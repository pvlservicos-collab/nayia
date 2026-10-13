CREATE OR REPLACE FUNCTION public.olx_anuncios_candidatos()
 RETURNS TABLE(codigo integer, negocio text, m jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT i.codigo, n.negocio, olx_anuncio_montar(i.codigo, n.negocio)
    FROM imoveis i
    CROSS JOIN LATERAL (SELECT 'venda'::text AS negocio WHERE coalesce(i.valor_venda, 0) > 0
                        UNION ALL SELECT 'locacao' WHERE coalesce(i.valor_aluguel, 0) > 0) n
   WHERE i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
     AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false);
$function$;
