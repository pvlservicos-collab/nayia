CREATE OR REPLACE FUNCTION public.site_imovel_publico(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH i AS (
    SELECT im.*, coalesce(im.extras, '{}'::jsonb) AS x,
           initcap(split_part(coalesce(im.tipo, 'Imóvel'), ' ', 1)) AS tipo_curto
      FROM imoveis im
     WHERE im.codigo = p_codigo AND im.publicado_no_site AND im.disponivel AND NOT coalesce(im.bloqueado, false)
  ), t AS (
    SELECT i.*, coalesce(nullif(btrim(i.tipo), ''), 'Imóvel')
           || CASE WHEN coalesce(i.quartos, 0) > 0 THEN ' ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
           || CASE WHEN nullif(btrim(i.condominio_nome), '') IS NOT NULL THEN ' no ' || btrim(i.condominio_nome)
                   WHEN nullif(btrim(i.bairro), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END AS titulo
      FROM i
  ), condo AS (
    -- 346: as características do CONDOMÍNIO vêm da ficha dele (lazer, segurança, comodidades); sem ficha, as do anúncio
    SELECT coalesce(
             (SELECT nullif(cf.lazer || cf.seguranca || cf.comodidades, '{}') FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id),
             (SELECT f.caracteristicas_condominio FROM imovel_ficha f WHERE f.codigo = p_codigo),
             '{}'::text[]) AS tags,
           (SELECT jsonb_strip_nulls(jsonb_build_object('nome', cf.nome, 'tipo', cf.tipo, 'torres', cf.torres, 'andares', cf.andares,
                      'aptos_por_andar', cf.aptos_por_andar, 'elevador', cf.elevador, 'construtora', cf.construtora,
                      'ano', coalesce(cf.ano_construcao, cf.ano_lancamento::text), 'taxas', nullif(cf.taxas, '[]'::jsonb),
                      'taxa_inclui', nullif(to_jsonb(cf.taxa_inclui), '[]'::jsonb)))   -- 448: o que a taxa inclui
              FROM t JOIN condominio_ficha cf ON cf.condominio_id = t.condo_id) AS ficha
  )
  SELECT jsonb_build_object(
    'codigo', t.codigo,
    'titulo', t.titulo,
    'slug', btrim(regexp_replace(lower(nay_sem_acento(t.titulo)), '[^a-z0-9]+', '-', 'g'), '-'),
    'parceiro', coalesce(t.e_parceiro, false),
    -- imóvel de parceiro não sai pela caixa (parceria nunca sai): a página nem oferece o envio
    'pode_enviar', NOT coalesce(t.e_parceiro, false),
    'local', jsonb_build_object('condominio', nullif(btrim(t.condominio_nome), ''), 'bairro', t.bairro,
                                'cidade', coalesce(t.cidade, 'Manaus'), 'estado', coalesce(t.estado, 'AM')),
    'carac', jsonb_build_object(
      'tipo', t.tipo, 'quartos', t.quartos, 'suites', t.suites, 'banheiros', t.banheiros,
      'salas', t.x ->> 'salas', 'vagas', t.vagas, 'vagascob', t.vagas_cobertas,
      'mobilia', t.mobilia, 'face', t.sol,
      'areautil', t.area_util, 'areatotal', t.area_total, 'areacons', t.x ->> 'area construida',
      'terreno', t.x ->> 'tamanho do terreno', 'frente', t.x ->> 'frente', 'fundo', t.x ->> 'fundo',
      'pedireito', t.x ->> 'pe direito', 'andares', t.x ->> 'andares', 'elevadores', t.x ->> 'elevadores',
      'escadas', t.x ->> 'lances de escada',
      'cobertura', CASE WHEN t.cobertura THEN coalesce(t.x ->> 'tipo de cobertura', 'Sim') WHEN t.cobertura = false THEN NULL ELSE t.x ->> 'tipo de cobertura' END,
      'mobilia_nivel', nay_mobilia_nivel(t.mobilia)),
    'condo', (SELECT ficha FROM condo),
    'tagscondo', to_jsonb((SELECT tags FROM condo)),
    'tagsimovel', to_jsonb(coalesce(
        (SELECT array_agg(c) FROM unnest(coalesce(nullif(t.caracteristicas, '{}'),
                 (SELECT f.caracteristicas_imovel FROM imovel_ficha f WHERE f.codigo = p_codigo), '{}'::text[])) c
          WHERE NOT EXISTS (SELECT 1 FROM condo, unnest(condo.tags) ct WHERE ct = c)), '{}'::text[])),
    'valores', jsonb_build_object('aluguel', t.valor_aluguel, 'venda', t.valor_venda, 'condo', t.taxa_condominio,
                                  'iptu', t.iptu, 'fin', t.x ->> 'aceita financiamento', 'permuta', t.x ->> 'permuta'),
    'incluso', t.x ->> 'incluso no aluguel',
    'garantia', t.x ->> 'garantia de aluguel',
    'desc', t.descricao,
    'fotos', coalesce((SELECT jsonb_agg(f.url ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id)
                         FROM imovel_fotos f
                        WHERE f.codigo = p_codigo AND coalesce(f.url, '') <> '' AND NOT coalesce(f.e_mosaico, false)), '[]'::jsonb),
    -- a posição vai ARREDONDADA (3 casas, ~110 m): a página mostra a região, não a porta
    'geo', (SELECT jsonb_build_object('lat', round(g.lat::numeric, 3), 'lon', round(g.lon::numeric, 3), 'precisao', g.precisao)
              FROM imovel_geo g WHERE g.codigo = p_codigo)
  ) FROM t;
$function$;
