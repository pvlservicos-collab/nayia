CREATE OR REPLACE FUNCTION public.site_scrap_anuncios(p_telefone text, p_lista bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'olx_id', a.olx_id, 'titulo', a.titulo, 'preco', a.preco, 'preco_texto', a.preco_texto, 'categoria', a.categoria,
           'tipo_negocio', a.tipo_negocio, 'quartos', a.quartos, 'area_m2', a.area_m2, 'bairro', a.bairro, 'cep', a.cep,
           'anunciante', a.anunciante, 'telefones', (SELECT array_agg(scrap_telefone_formatar(t)) FROM unnest(a.telefones) t),
           'telefone_mascarado', a.telefone_mascarado, 'descricao', a.descricao, 'url', a.url, 'foto', a.fotos[1], 'n_fotos', a.n_fotos,
           'data_olx', a.data_olx, 'lista', l.nome) ORDER BY a.data_olx DESC NULLS LAST), '[]'::jsonb)
    FROM scrap_anuncio a JOIN scrap_lista l ON l.id = a.lista_id
   WHERE scrap_telefone_normalizar(p_telefone) = ANY (a.telefones)
     AND (p_lista IS NULL OR a.lista_id = p_lista)
$function$;
