CREATE OR REPLACE FUNCTION public.crm_anuncio_mesma_unidade(p jsonb, p_cand jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH a AS (
    SELECT crm_anuncio_numero(p -> 'preco') AS preco,
           crm_anuncio_numero(p -> 'area_m2') AS area,
           crm_anuncio_numero(p -> 'quartos') AS quartos,
           nullif(p_cand -> 'entendido' ->> 'condominio', '') AS condo,
           crm_anuncio_nome_palavras(p ->> 'anunciante_nome') AS nome
  ),
  c AS (
    SELECT (x ->> 'id_imovel')::int AS codigo, coalesce((x ->> 'score')::int, 0) AS score,
           coalesce(x -> 'campos_que_bateram', '[]'::jsonb) AS bateu,
           (coalesce(x -> 'campos_divergentes', '[]'::jsonb) @> '[{"campo": "condominio_nome"}]'::jsonb) AS x_condo,
           (x -> 'dados' ->> 'preco')::numeric AS preco,
           (x -> 'dados' ->> 'area_m2')::numeric AS area,
           (x -> 'dados' ->> 'quartos')::numeric AS quartos,
           coalesce((x -> 'dados' ->> 'no_mercado')::boolean, false) AS no_mercado,
           x -> 'dados' ->> 'status' AS status
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_cand -> 'candidatos') = 'array'
                                     THEN p_cand -> 'candidatos' ELSE '[]'::jsonb END) x
     WHERE (x ->> 'id_imovel') ~ '^[0-9]+$'
  ),
  s AS (
    SELECT c.codigo, c.score, c.status, c.no_mercado,
           c.bateu ? 'link' AS m_link,
           ((a.condo IS NOT NULL AND n.nucleo IS NOT NULL
             AND (n.nucleo = a.condo OR crm_anuncio_palavras(n.nucleo) = crm_anuncio_palavras(a.condo)))
            OR ((c.bateu ? 'endereco' OR c.bateu ? 'cep') AND NOT c.x_condo)) AS m_lugar,
           c.x_condo,
           c.bateu ? 'bairro' AS m_bairro,
           c.bateu ? 'tipo' AS m_tipo,
           (a.area IS NOT NULL AND c.area IS NOT NULL AND abs(c.area - a.area) <= a.area * 0.03) AS m_area,
           (a.area IS NOT NULL AND c.area IS NOT NULL AND abs(c.area - a.area) > a.area * 0.10) AS x_area,
           (a.area IS NULL OR c.area IS NULL) AS sem_area,
           (a.preco IS NOT NULL AND c.preco IS NOT NULL AND abs(c.preco - a.preco) <= a.preco * 0.02) AS m_preco,
           (a.quartos IS NOT NULL AND c.quartos IS NOT NULL AND c.quartos = a.quartos) AS m_quartos,
           (a.quartos IS NOT NULL AND c.quartos IS NOT NULL AND c.quartos <> a.quartos) AS x_quartos,
           (a.nome[1] IS NOT NULL AND d.nome[1] = a.nome[1]
             AND (cardinality(a.nome) = 1 OR cardinality(d.nome) = 1 OR a.nome[2:] && d.nome[2:])) AS m_nome
      FROM c
      CROSS JOIN a
      JOIN imoveis i ON i.codigo = c.codigo
      LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
      LEFT JOIN proprietarios pr ON pr.id = coalesce(i.proprietario_id, ip.proprietario_id)
      CROSS JOIN LATERAL (SELECT nullif(nay_sem_acento(lower(nai_condominio_nucleo(coalesce(i.condominio_nome, '')))), '') AS nucleo) n
      CROSS JOIN LATERAL (SELECT crm_anuncio_nome_palavras(pr.nome) AS nome) d
  ),
  v AS (
    SELECT s.*,
           CASE WHEN s.m_link THEN 'link'
                WHEN s.x_area OR s.x_quartos THEN NULL
                WHEN s.m_lugar AND s.m_nome AND (s.m_area OR s.m_preco) THEN 'dono'
                WHEN s.no_mercado AND s.m_lugar AND s.m_preco AND (s.m_area OR (s.sem_area AND s.m_quartos)) THEN 'unidade'
                WHEN s.no_mercado AND s.m_bairro AND NOT s.x_condo AND s.m_tipo AND s.m_area AND s.m_preco AND s.m_quartos THEN 'unidade'
           END AS nivel
      FROM s
  )
  SELECT jsonb_build_object('codigo', v.codigo, 'nivel', v.nivel, 'status', v.status,
           'sinais', to_jsonb(array_remove(ARRAY[
              CASE WHEN v.m_link THEN 'link' END,
              CASE WHEN v.m_lugar THEN 'lugar' END,
              CASE WHEN v.m_nome THEN 'nome do dono' END,
              CASE WHEN v.m_area THEN 'area' END,
              CASE WHEN v.m_preco THEN 'preco' END,
              CASE WHEN v.m_quartos THEN 'quartos' END,
              CASE WHEN v.m_bairro THEN 'bairro' END], NULL)))
    FROM v
   WHERE v.nivel IS NOT NULL
   ORDER BY array_position(ARRAY['link', 'dono', 'unidade'], v.nivel), v.score DESC, v.codigo
   LIMIT 1;
$function$;
