-- anúncios de particular da lista "OLX · Recentes de Manaus" (30), com quantos anúncios o mesmo nome tem
SELECT * FROM (
  WITH nomes AS (
    SELECT lower(trim(anunciante)) n, count(DISTINCT olx_id) total,
           count(DISTINCT olx_id) FILTER (WHERE dados->>'tipo_anunciante' = 'profissional') pro
      FROM scrap_anuncio WHERE coalesce(anunciante, '') <> '' GROUP BY 1)
  SELECT json_agg(json_build_object(
           'olx_id', a.olx_id, 'url', a.url, 'busca', a.dados->>'busca', 'anunciante', a.anunciante, 'titulo', a.titulo,
           'preco', a.preco, 'bairro', a.bairro, 'tipo_negocio', a.tipo_negocio, 'categoria', a.categoria,
           'data_olx', a.data_olx, 'nome_total', n.total, 'nome_pro', n.pro))
    FROM scrap_anuncio a LEFT JOIN nomes n ON n.n = lower(trim(a.anunciante))
   WHERE a.lista_id = 30 AND a.dados->>'tipo_anunciante' = 'particular'
) z;
