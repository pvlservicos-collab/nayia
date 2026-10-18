CREATE OR REPLACE FUNCTION public.site_scrap_importar(p jsonb, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_lista bigint; v_nome text; v_n int; v_contatos int; v_sem int;
BEGIN
  v_lista := nullif(p->'lista'->>'id', '')::bigint;
  v_nome := nullif(trim(p->'lista'->>'nome'), '');
  IF v_lista IS NULL AND v_nome IS NOT NULL THEN SELECT id INTO v_lista FROM scrap_lista WHERE nome = v_nome LIMIT 1; END IF;
  IF v_lista IS NULL THEN
    IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'a lista precisa de nome'); END IF;
    INSERT INTO scrap_lista (nome, descricao, origem, url_busca, cor, ordem, criado_por)
    VALUES (v_nome, p->'lista'->>'descricao', 'olx', p->'lista'->>'url_busca', coalesce(nullif(p->'lista'->>'cor', ''), '#6d28d9'),
            coalesce((SELECT max(ordem) + 1 FROM scrap_lista), 0), p_quem)
    RETURNING id INTO v_lista;
  ELSE
    UPDATE scrap_lista SET url_busca = coalesce(nullif(p->'lista'->>'url_busca', ''), url_busca), atualizado_em = now() WHERE id = v_lista;
  END IF;

  INSERT INTO scrap_anuncio AS a (lista_id, olx_id, titulo, preco, preco_texto, preco_antigo, categoria, tipo_negocio, subtipo, quartos, banheiros,
                                  vagas, area_m2, condominio, iptu, bairro, cep, lat, lng, anunciante, anunciante_id, telefone_mascarado,
                                  descricao, fotos, n_fotos, url, data_olx, publicado_em, dados)
  SELECT v_lista, (x->>'olx_id')::bigint, x->>'titulo', (x->>'preco')::numeric, x->>'preco_texto', x->>'preco_antigo', x->>'categoria',
         x->>'tipo_negocio', x->>'subtipo', (x->>'quartos')::int, (x->>'banheiros')::int, (x->>'vagas')::int, (x->>'area_m2')::numeric,
         (x->>'condominio_valor')::numeric, (x->>'iptu_valor')::numeric, x->>'bairro', x->>'cep', (x->>'lat')::double precision,
         (x->>'lng')::double precision, nullif(trim(x->>'anunciante'), ''), x->>'anunciante_id', x->>'telefone_mascarado', x->>'descricao',
         coalesce((SELECT array_agg(f) FROM jsonb_array_elements_text(coalesce(x->'fotos', '[]'::jsonb)) f), '{}'),
         (x->>'n_fotos')::int, x->>'url', (x->>'data')::timestamptz, (x->>'publicado_em')::timestamptz,
         coalesce(x->'dados', '{}'::jsonb)
    FROM jsonb_array_elements(coalesce(p->'anuncios', '[]'::jsonb)) x
   WHERE (x->>'olx_id') IS NOT NULL
  ON CONFLICT (lista_id, olx_id) DO UPDATE SET
    titulo = EXCLUDED.titulo, preco = EXCLUDED.preco, preco_texto = EXCLUDED.preco_texto, preco_antigo = EXCLUDED.preco_antigo,
    categoria = EXCLUDED.categoria, tipo_negocio = EXCLUDED.tipo_negocio, subtipo = EXCLUDED.subtipo, quartos = EXCLUDED.quartos,
    banheiros = EXCLUDED.banheiros, vagas = EXCLUDED.vagas, area_m2 = EXCLUDED.area_m2, condominio = EXCLUDED.condominio, iptu = EXCLUDED.iptu,
    bairro = EXCLUDED.bairro, cep = coalesce(EXCLUDED.cep, a.cep), lat = coalesce(EXCLUDED.lat, a.lat), lng = coalesce(EXCLUDED.lng, a.lng),
    anunciante = coalesce(EXCLUDED.anunciante, a.anunciante), anunciante_id = coalesce(EXCLUDED.anunciante_id, a.anunciante_id),
    telefone_mascarado = coalesce(EXCLUDED.telefone_mascarado, a.telefone_mascarado), descricao = coalesce(EXCLUDED.descricao, a.descricao),
    fotos = CASE WHEN cardinality(EXCLUDED.fotos) > 0 THEN EXCLUDED.fotos ELSE a.fotos END, n_fotos = coalesce(EXCLUDED.n_fotos, a.n_fotos),
    url = coalesce(EXCLUDED.url, a.url), data_olx = coalesce(EXCLUDED.data_olx, a.data_olx), publicado_em = coalesce(EXCLUDED.publicado_em, a.publicado_em),
    dados = a.dados || EXCLUDED.dados, coletado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_contatos := scrap_contatos_rebuild(v_lista);
  SELECT count(*) INTO v_sem FROM scrap_anuncio WHERE lista_id = v_lista AND cardinality(telefones) = 0;
  RETURN jsonb_build_object('ok', true, 'lista_id', v_lista, 'anuncios', v_n, 'contatos', v_contatos, 'anuncios_sem_telefone', v_sem);
END
$function$;
