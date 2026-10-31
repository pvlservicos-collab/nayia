CREATE OR REPLACE FUNCTION public.crm_olx_scrap_busca(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_fin   text := lower(coalesce(p->>'finalidade', ''));
  v_q     text := nullif(btrim(coalesce(p->>'q', '')), '');
  v_tipos text[] := ARRAY(SELECT lower(jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'tipos') = 'array' THEN p->'tipos' ELSE '[]'::jsonb END)));
  v_subs  text[] := ARRAY(SELECT lower(jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'subtipos') = 'array' THEN p->'subtipos' ELSE '[]'::jsonb END)));
  v_bairros text[] := ARRAY(SELECT DISTINCT nay_normalizar_lugar(coalesce(nay_bairro_parecido(b), b), true)
                              FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'bairros') = 'array' THEN p->'bairros' ELSE '[]'::jsonb END) b);
  v_qts   int[] := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'quartos') = 'array' THEN p->'quartos' ELSE '[]'::jsonb END)::int);
  v_ban   int[] := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'banheiros') = 'array' THEN p->'banheiros' ELSE '[]'::jsonb END)::int);
  v_vag   int[] := ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'vagas') = 'array' THEN p->'vagas' ELSE '[]'::jsonb END)::int);
  v_pmin  numeric := nullif(p->>'preco_min', '')::numeric;
  v_pmax  numeric := nullif(p->>'preco_max', '')::numeric;
  v_amin  numeric := nullif(p->>'area_min', '')::numeric;
  v_amax  numeric := nullif(p->>'area_max', '')::numeric;
  v_quem  text := lower(coalesce(p->>'quem', ''));
  v_tel   boolean := coalesce(p->>'com_telefone', '') = 'true';
  v_dias  int := nullif(p->>'dias', '')::int;
  v_ordem text := coalesce(p->>'ordem', 'recentes');
  v_por   int := least(greatest(coalesce(nullif(p->>'por', '')::int, 24), 1), 60);
  v_pag   int := greatest(coalesce(nullif(p->>'pagina', '')::int, 1), 1);
  v_total int;
  v_itens jsonb;
BEGIN
  SELECT coalesce(max(tot), 0), coalesce(jsonb_agg(it ORDER BY ord) FILTER (WHERE ord > (v_pag - 1) * v_por AND ord <= v_pag * v_por), '[]'::jsonb)
    INTO v_total, v_itens
    FROM (
      SELECT jsonb_build_object(
               'olx_id', a.olx_id, 'titulo', a.titulo, 'preco', a.preco, 'preco_texto', a.preco_texto, 'preco_antigo', a.preco_antigo,
               'categoria', a.categoria, 'tipo_negocio', a.tipo_negocio, 'subtipo', a.subtipo, 'quartos', a.quartos, 'banheiros', a.banheiros,
               'vagas', a.vagas, 'area_m2', a.area_m2, 'condominio', a.condominio, 'iptu', a.iptu, 'bairro', a.bairro,
               'anunciante', a.anunciante, 'telefones', a.telefones, 'telefone_mascarado', a.telefone_mascarado,
               'fotos', a.fotos[1:4], 'n_fotos', a.n_fotos, 'url', a.url, 'data_olx', a.data_olx, 'coletado_em', a.coletado_em,
               'lista', a.lista, 'descricao', left(a.descricao, 600)) AS it,
             row_number() OVER (ORDER BY
               CASE v_ordem WHEN 'menor_preco' THEN nullif(a.preco, 0) END ASC NULLS LAST,
               CASE v_ordem WHEN 'maior_preco' THEN a.preco END DESC NULLS LAST,
               CASE v_ordem WHEN 'maior_area' THEN a.area_m2 END DESC NULLS LAST,
               a.data_olx DESC NULLS LAST, a.olx_id DESC) AS ord,
             count(*) OVER () AS tot
        FROM (
          SELECT DISTINCT ON (a.olx_id) a.*, l.nome AS lista
            FROM scrap_anuncio a JOIN scrap_lista l ON l.id = a.lista_id
           WHERE (v_fin = '' OR (v_fin LIKE 'loca%' AND a.tipo_negocio ILIKE 'Aluguel%') OR (v_fin LIKE 'vend%' AND a.tipo_negocio ILIKE 'Venda%'))
             AND (cardinality(v_tipos) = 0
                  OR ('apartamento' = ANY (v_tipos) AND a.categoria = 'Apartamentos')
                  OR ('casa' = ANY (v_tipos) AND a.categoria = 'Casas')
                  OR ('casa_condominio' = ANY (v_tipos) AND a.tipo_negocio ILIKE '%condom%'))
             AND (cardinality(v_subs) = 0 OR lower(coalesce(a.subtipo, '')) = ANY (v_subs))
             AND (cardinality(v_bairros) = 0 OR nay_normalizar_lugar(a.bairro, true) = ANY (v_bairros))
             AND (v_pmin IS NULL OR a.preco >= v_pmin) AND (v_pmax IS NULL OR a.preco <= v_pmax)
             AND (v_amin IS NULL OR a.area_m2 >= v_amin) AND (v_amax IS NULL OR a.area_m2 <= v_amax)
             AND (cardinality(v_qts) = 0 OR a.quartos = ANY (v_qts) OR (5 = ANY (v_qts) AND a.quartos >= 5))
             AND (cardinality(v_ban) = 0 OR a.banheiros = ANY (v_ban) OR (5 = ANY (v_ban) AND a.banheiros >= 5))
             AND (cardinality(v_vag) = 0 OR a.vagas = ANY (v_vag) OR (5 = ANY (v_vag) AND a.vagas >= 5))
             AND (v_quem = '' OR (v_quem = 'corretores' AND l.nome ILIKE '%Corretores%') OR (v_quem = 'imobiliarias' AND l.nome ILIKE '%Imobili%'))
             AND (NOT v_tel OR cardinality(a.telefones) > 0)
             AND (v_dias IS NULL OR a.coletado_em > now() - make_interval(days => v_dias))
             AND (v_q IS NULL OR a.titulo ILIKE '%' || v_q || '%' OR a.descricao ILIKE '%' || v_q || '%' OR a.bairro ILIKE '%' || v_q || '%'
                  OR a.anunciante ILIKE '%' || v_q || '%' OR a.olx_id::text = v_q)
           ORDER BY a.olx_id, a.coletado_em DESC) a) z;
  RETURN jsonb_build_object('total', v_total, 'pagina', v_pag, 'por', v_por, 'itens', v_itens);
END;
$function$;
