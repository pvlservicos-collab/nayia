CREATE OR REPLACE FUNCTION public.site_blog_card_imovel(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
           'codigo', b.codigo, 'tipo', coalesce(b.tipo_original, b.tipo), 'condominio', b.condominio_nome, 'bairro', b.bairro,
           'quartos', b.quartos, 'suites', b.suites, 'vagas', b.vagas, 'area_util', b.area_util,
           'valor_venda', nullif(b.valor_venda, 0), 'valor_aluguel', nullif(b.valor_aluguel, 0),
           'capa', (SELECT f.url FROM imovel_fotos f WHERE f.codigo = b.codigo
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1),
           'url', 'https://imobeasy.online/imovel/' || b.codigo)
    FROM core_imovel_busca b
   WHERE b.codigo = p_codigo AND b.ofertavel AND NOT coalesce(b.e_parceiro, false)
$function$;
