CREATE OR REPLACE FUNCTION public.crm_captacao_cadastro_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH dos_imoveis AS (
    SELECT i.condo_id,
           count(*)                                                                   AS imoveis,
           count(*) FILTER (WHERE coalesce(i.logradouro, '') <> '')                    AS base,
           mode() WITHIN GROUP (ORDER BY i.logradouro) FILTER (WHERE coalesce(i.logradouro, '') <> '') AS logradouro,
           mode() WITHIN GROUP (ORDER BY i.bairro)     FILTER (WHERE coalesce(i.bairro, '') <> '')     AS bairro,
           mode() WITHIN GROUP (ORDER BY i.cidade)     FILTER (WHERE coalesce(i.cidade, '') <> '')     AS cidade,
           mode() WITHIN GROUP (ORDER BY i.estado)     FILTER (WHERE coalesce(i.estado, '') <> '')     AS estado
      FROM imoveis i
     WHERE i.condo_id IS NOT NULL
     GROUP BY i.condo_id
  ),
  conds AS (
    SELECT c.id, c.nome,
           coalesce(nullif(btrim(c.bairro), ''), d.bairro)                   AS bairro,
           coalesce(nullif(btrim(f.endereco), ''), d.logradouro)             AS endereco,
           CASE WHEN nullif(btrim(f.endereco), '') IS NOT NULL THEN 'ficha'
                WHEN d.logradouro IS NOT NULL THEN 'imoveis' END             AS endereco_de,
           coalesce(d.base, 0)                                               AS base,
           coalesce(d.cidade, 'Manaus')                                      AS cidade,
           coalesce(d.estado, 'AM')                                          AS estado,
           coalesce(d.imoveis, 0)                                            AS imoveis,
           nullif(btrim(f.andares), '')                                       AS andares,
           nullif(btrim(f.elevador), '')                                      AS elevador,
           nullif(btrim(f.torres), '')                                        AS torres,
           nullif(btrim(f.construtora), '')                                   AS construtora,
           coalesce(f.lazer, '{}'::text[])                                    AS lazer
      FROM condominios c
      LEFT JOIN dos_imoveis d ON d.condo_id = c.id
      LEFT JOIN condominio_ficha f ON f.condominio_id = c.id
  ),
  carac AS (
    SELECT x AS nome, count(*) AS usos
      FROM imoveis, unnest(caracteristicas) x
     WHERE btrim(x) <> ''
     GROUP BY x
  ),
  -- O PRÉ-CADASTRO: todo imóvel que está em Rascunho (o que entra pela OLX fica
  -- assim até alguém cadastrar). `origem` diz de onde veio: 'olx', 'site',
  -- 'captacao', a planilha do site antigo.
  rascunhos AS (
    SELECT i.codigo, coalesce(nullif(btrim(i.tipo), ''), '')           AS tipo,
           coalesce(nullif(btrim(i.bairro), ''), '')                    AS bairro,
           coalesce(nullif(btrim(i.condominio_nome), ''), '')           AS condominio,
           i.condo_id, coalesce(i.origem, '')                           AS origem,
           coalesce(i.valor_aluguel, 0)                                 AS aluguel,
           coalesce(i.valor_venda, 0)                                   AS venda,
           (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo) AS fotos,
           p.nome                                                       AS dono,
           i.criado_em
      FROM imoveis i
      LEFT JOIN proprietarios p ON p.id = i.proprietario_id
     WHERE i.status = 'Rascunho'
  )
  SELECT jsonb_build_object(
    'condominios', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'nome', nome, 'bairro', bairro, 'endereco', endereco, 'enderecoDe', endereco_de,
        'base', base, 'cidade', cidade, 'estado', estado, 'imoveis', imoveis,
        'andares', andares, 'elevador', elevador, 'torres', torres, 'construtora', construtora,
        'lazer', to_jsonb(lazer)) ORDER BY nome) FROM conds), '[]'::jsonb),
    'caracteristicas', coalesce((SELECT jsonb_agg(jsonb_build_object('nome', nome, 'usos', usos)
        ORDER BY usos DESC, nome) FROM carac), '[]'::jsonb),
    'tipos', coalesce((SELECT jsonb_agg(DISTINCT btrim(tipo)) FROM imoveis WHERE coalesce(btrim(tipo), '') <> ''), '[]'::jsonb),
    'bairros', coalesce((SELECT jsonb_agg(b ORDER BY b) FROM (
        SELECT DISTINCT btrim(bairro) AS b FROM imoveis WHERE coalesce(btrim(bairro), '') <> '') x), '[]'::jsonb),
    'rascunhos', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'codigo', codigo, 'tipo', tipo, 'bairro', bairro, 'condominio', condominio, 'condoId', condo_id,
        'origem', origem, 'aluguel', aluguel, 'venda', venda, 'fotos', fotos, 'dono', dono,
        'criado', criado_em) ORDER BY criado_em DESC NULLS LAST, codigo DESC) FROM rascunhos), '[]'::jsonb)
  )
$function$;
