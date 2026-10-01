CREATE OR REPLACE FUNCTION public.crm_imovel_para_cadastro(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'codigo', i.codigo, 'status', i.status, 'origem', i.origem,
    'tipo', i.tipo, 'bairro', i.bairro, 'condominio', i.condominio_nome, 'condoId', i.condo_id,
    'logradouro', i.logradouro, 'numero', i.numero, 'complemento', i.complemento,
    'cidade', i.cidade, 'estado', i.estado,
    'quartos', i.quartos, 'suites', i.suites, 'banheiros', i.banheiros,
    'vagas', i.vagas, 'vagasCobertas', i.vagas_cobertas,
    'areaUtil', i.area_util, 'areaTotal', i.area_total,
    'andar', i.andar, 'sol', i.sol, 'mobilia', i.mobilia,
    'taxaCondominio', i.taxa_condominio, 'iptu', i.iptu,
    'aluguel', i.valor_aluguel, 'venda', i.valor_venda,
    'caracteristicas', to_jsonb(coalesce(i.caracteristicas, '{}'::text[])),
    'descricao', i.descricao,
    'inclusoNoAluguel', i.extras->>'incluso no aluguel',
    'temDono', i.proprietario_id IS NOT NULL,
    'dono', (SELECT p.nome FROM proprietarios p WHERE p.id = i.proprietario_id),
    'fotos', (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo),
    'pontuacao', nai_imovel_pontos(i.codigo))
    FROM imoveis i
   WHERE i.codigo = p_codigo
$function$;
