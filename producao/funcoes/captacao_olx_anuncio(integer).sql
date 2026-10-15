CREATE OR REPLACE FUNCTION public.captacao_olx_anuncio(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'codigo', i.codigo, 'tipo', i.tipo, 'titulo', coalesce(i.extras->>'olx_titulo', i.extras->>'titulo'),
    'negocio', CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' ELSE 'venda' END,
    'valor_venda', nullif(i.valor_venda, 0), 'valor_aluguel', nullif(i.valor_aluguel, 0),
    'condominio', nullif(btrim(coalesce(i.condominio_nome, '')), ''), 'bairro', i.bairro,
    'taxa_condominio', nullif(i.taxa_condominio, 0), 'iptu', nullif(i.iptu, 0),
    'andar', nullif(btrim(coalesce(i.andar, '')), ''), 'sol', nullif(btrim(coalesce(i.sol, '')), ''),
    'area_util', nullif(i.area_util, 0), 'area_total', nullif(i.area_total, 0),
    'logradouro', nullif(btrim(coalesce(i.logradouro, '')), ''), 'numero', nullif(btrim(coalesce(i.numero, '')), ''),
    'quartos', i.quartos, 'elevador', (SELECT cf.elevador FROM condominio_ficha cf WHERE cf.condominio_id = i.condo_id),
    'descricao', left(i.descricao, 1500), 'olx_id', i.extras->>'olx_id'))
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;
