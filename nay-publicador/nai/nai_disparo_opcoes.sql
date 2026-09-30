CREATE OR REPLACE FUNCTION public.nai_disparo_opcoes()
 RETURNS TABLE(campo text, valor text, n integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH ok AS (
    SELECT i.* FROM imoveis i
     WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND nai_imovel_disponivel(i.codigo)
  )
  SELECT 'bairro', btrim(bairro), count(*)::int FROM ok WHERE coalesce(btrim(bairro), '') <> '' GROUP BY 2
  UNION ALL
  SELECT 'tipo', btrim(tipo), count(*)::int FROM ok WHERE coalesce(btrim(tipo), '') <> '' GROUP BY 2
  ORDER BY 1, 3 DESC, 2;
$function$
;
