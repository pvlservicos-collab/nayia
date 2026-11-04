CREATE OR REPLACE FUNCTION public.crm_olx_captar()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  -- 603 (Pedro, 04/11): só aluguel a partir de R$ 2.500, venda a partir de R$ 200 mil e imóvel em condomínio
  WITH base AS MATERIALIZED (SELECT * FROM olx_captar WHERE fora IS NULL
        AND ((tipo_negocio ILIKE 'Aluguel%' AND coalesce(preco, 0) >= 2500) OR (tipo_negocio ILIKE 'Venda%' AND coalesce(preco, 0) >= 200000))
        AND (categoria = 'Apartamentos' OR tipo_negocio ILIKE '%condomin%')),
  chaves AS MATERIALIZED (SELECT DISTINCT unnest(telefones) t FROM base),
  ch AS MATERIALIZED (SELECT t, nay_fone_chave(nay_fone_com_ddi(t)) AS chave FROM chaves),
  conhecido AS MATERIALIZED (
    SELECT DISTINCT ON (chave) chave, motivo FROM (
      SELECT nay_fone_chave(nay_fone_com_ddi(x.telefone)) chave, 'corretor que já conhecemos' motivo, 1 o
        FROM corretores x WHERE coalesce(x.telefone, '') <> ''
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(x.telefone)), 'proprietário que já conhecemos', 2
        FROM proprietarios x WHERE coalesce(x.telefone, '') <> ''
      UNION ALL SELECT f.chave, 'já falamos (' || array_to_string(f.origens, ', ') || ')', 3 FROM privado.falou_conosco f
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(t, '\D', '', 'g'))), 'já falamos pela Parceria', 4
        FROM (SELECT DISTINCT telefone t FROM mensagens WHERE coalesce(telefone, '') !~ '@') m
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(t, '\D', '', 'g'))), 'já falamos pelo Leads/Oficial', 5
        FROM (SELECT DISTINCT telefone t FROM captacao_mensagens) m
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(n.chave)), 'já falou com a Nay', 6 FROM nai_contato n WHERE n.chave !~ '(@|lid)'
      UNION ALL SELECT scrap_chave(s.telefone), 'está no Scrap: ' || l.nome, 7
        FROM scrap_contato s JOIN scrap_lista l ON l.id = s.lista_id
       WHERE l.pasta IN ('Base', 'Blacklist') OR (l.pasta = 'OLX' AND l.nome ~* '(corretor|imobili)')
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(a.telefone, '\D', '', 'g'))), 'o bot da OLX já falou com ele', 8
        FROM privado.anuncio_consulta a WHERE coalesce(a.telefone, '') <> ''
    ) z WHERE chave IN (SELECT chave FROM ch WHERE chave IS NOT NULL)
    ORDER BY chave, o),
  anuncio_falado AS MATERIALIZED (
    SELECT DISTINCT o FROM (
      SELECT (extras->>'olx_id')::text o FROM imoveis WHERE extras ? 'olx_id'
      UNION ALL SELECT id_anuncio FROM privado.anuncio_consulta WHERE id_anuncio IS NOT NULL
      UNION ALL SELECT substring(link from '(\d{8,})(?:\D*$)') FROM privado.anuncio_consulta
      UNION ALL SELECT list_id FROM privado.olx_chat WHERE list_id IS NOT NULL
      UNION ALL SELECT substring(escolhido->>'url' from '(\d{8,})(?:\D*$)') FROM privado.olx_busca_parceiro WHERE escolhido IS NOT NULL
    ) y WHERE o IS NOT NULL),
  julgado AS MATERIALIZED (
    SELECT b.*,
           (SELECT k.motivo FROM ch JOIN conhecido k ON k.chave = ch.chave WHERE ch.t = ANY (b.telefones) LIMIT 1) AS motivo,
           (b.olx_id::text IN (SELECT o FROM anuncio_falado)) AS anuncio_ja
      FROM base b)
  SELECT jsonb_build_object(
    'itens', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'olx_id', j.olx_id, 'url', j.url, 'titulo', j.titulo, 'preco', j.preco, 'preco_texto', j.preco_texto,
        'tipo_negocio', j.tipo_negocio, 'categoria', j.categoria, 'bairro', j.bairro, 'quartos', j.quartos, 'area_m2', j.area_m2,
        'foto', j.foto, 'n_fotos', j.n_fotos, 'anunciante', j.anunciante, 'telefone', j.telefone, 'telefones', j.telefones,
        'whatsapp', j.whatsapp, 'descricao', left(j.descricao, 600), 'publicado_em', j.publicado_em, 'nota', j.nota,
        'sinais', j.sinais, 'chamado_em', j.chamado_em, 'chamado_por', j.chamado_por, 'chamado_como', j.chamado_como)
        ORDER BY (j.chamado_em IS NOT NULL), (j.telefone IS NULL), j.nota DESC, j.publicado_em DESC NULLS LAST)
      FROM julgado j WHERE j.motivo IS NULL AND NOT j.anuncio_ja), '[]'::jsonb),
    'fora', (SELECT coalesce(jsonb_object_agg(m, n), '{}'::jsonb) FROM (
        SELECT m, count(*) n FROM (
          SELECT fora m FROM olx_captar WHERE fora IS NOT NULL
          UNION ALL SELECT 'fora do filtro (aluguel a partir de R$ 2.500, venda a partir de R$ 200 mil, só em condomínio)'
            FROM olx_captar WHERE fora IS NULL AND NOT (((tipo_negocio ILIKE 'Aluguel%' AND coalesce(preco, 0) >= 2500) OR (tipo_negocio ILIKE 'Venda%' AND coalesce(preco, 0) >= 200000)) AND (categoria = 'Apartamentos' OR tipo_negocio ILIKE '%condomin%'))
          UNION ALL SELECT CASE WHEN anuncio_ja THEN 'anúncio que já cadastramos ou consultamos'
                                ELSE regexp_replace(motivo, ' \(.*$', '') END
            FROM julgado WHERE motivo IS NOT NULL OR anuncio_ja) q GROUP BY m) r),
    'carregado_em', (SELECT max(carregado_em) FROM olx_captar),
    'analisados', (SELECT count(*) FROM olx_captar))
$function$;
