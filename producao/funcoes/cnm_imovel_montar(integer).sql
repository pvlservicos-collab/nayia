CREATE OR REPLACE FUNCTION public.cnm_imovel_montar(p_codigo integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i        imoveis;
  cf       condominio_ficha;
  v_t      text;
  v_fin    text;                 -- RE ou CO
  v_tipo   text;                 -- o nome do tipo na lista do portal
  v_rot    text;                 -- o tipo como vai no título
  v_falta  text[] := '{}';
  v_venda  numeric;
  v_aluga  numeric;
  v_cep    text;
  v_fotos  jsonb;
  v_priv   text[];
  v_comum  text[];
  v_resto  text[];
  v_mob    text;
  v_cond   text;
  v_neg    text;
  v_tit    text;
  v_desc   text;
  v_pet    boolean;
  v_casa   boolean;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'falta', jsonb_build_array('o imóvel não está no cadastro'));
  END IF;
  v_venda := nullif(coalesce(i.valor_venda, 0), 0);
  v_aluga := nullif(coalesce(i.valor_aluguel, 0), 0);

  -- quem não vai (a mesma regra da OLX)
  IF i.status IS DISTINCT FROM 'Disponível' OR NOT coalesce(i.disponivel, false) THEN v_falta := v_falta || ('não está Disponível (' || coalesce(i.status, 'sem situação') || ')'); END IF;
  IF NOT coalesce(i.publicado_no_site, false) THEN v_falta := v_falta || 'fora do nosso site'::text; END IF;
  IF coalesce(i.e_parceiro, false) THEN v_falta := v_falta || 'imóvel de parceiro'::text; END IF;
  IF coalesce(i.bloqueado, false) THEN v_falta := v_falta || 'bloqueado'::text; END IF;
  IF v_venda IS NULL AND v_aluga IS NULL THEN v_falta := v_falta || 'sem valor de venda nem de aluguel'::text; END IF;

  -- o tipo: a lista do portal (residencial.html e comercial.html), com acento e espaço exatos
  v_t := lower(nay_sem_acento(coalesce(i.tipo, '')));
  v_casa := v_t ~ '^(casa|sobrado)';
  SELECT t.fin, t.tipo, t.rot INTO v_fin, v_tipo, v_rot FROM (VALUES
      (1, v_t ~ '^cobertura' OR (v_t ~ '^apartamento' AND coalesce(i.cobertura, false)), 'RE', 'Cobertura', 'Cobertura'),
      (2, v_t ~ '^apartamento', 'RE', 'Apartamento', 'Apartamento'),
      (3, v_t ~ '^flat', 'RE', 'Flat', 'Flat'),
      (4, v_t ~ '^(kitnet|kitinete|kit |studio|estudio|stúdio)', 'RE', 'Kitnet / Stúdio', 'Kitnet'),
      (5, v_t ~ '^loft', 'RE', 'Loft', 'Loft'),
      (6, v_casa AND v_t ~ 'condominio', 'RE', 'Casa / Sobrado em Condomínio', 'Casa em condomínio'),
      (7, v_casa, 'RE', 'Casa / Sobrado', 'Casa'),
      (8, v_t ~ '^(lote|terreno)' AND v_t ~ 'condominio', 'RE', 'Terreno em Condomínio', 'Terreno em condomínio'),
      (9, v_t ~ '^(lote|terreno|area)', 'RE', 'Terreno / Lote', 'Terreno'),
      (10, v_t ~ '^(sitio|chacara)', 'RE', 'Sítio / Chácara', 'Sítio'),
      (11, v_t ~ '^fazenda', 'CO', 'Fazenda', 'Fazenda'),
      (12, v_t ~ '^(sala|andar|conjunto)', 'CO', 'Conj. Comercial / Sala', 'Sala comercial'),
      (13, v_t ~ '^(loja|ponto)', 'CO', 'Loja / Comércio', 'Loja'),
      (14, v_t ~ '^(galpao|deposito|barracao)', 'CO', 'Barracão / Galpão', 'Galpão'),
      (15, v_t ~ '^(predio|edificio)', 'CO', 'Edifício', 'Prédio'),
      (16, v_t ~ '^consultorio', 'CO', 'Consultório', 'Consultório'),
      (17, v_t ~ '^garagem', 'CO', 'Garagem', 'Garagem')
    ) AS t(ordem, vale, fin, tipo, rot)
   WHERE t.vale ORDER BY t.ordem LIMIT 1;
  IF v_tipo IS NULL THEN
    v_falta := v_falta || ('tipo sem par no Chaves na Mão (' || coalesce(nullif(btrim(i.tipo), ''), 'sem tipo') || ')');
  END IF;
  IF nullif(btrim(coalesce(i.bairro, '')), '') IS NULL THEN v_falta := v_falta || 'sem bairro'::text; END IF;

  -- as fotos: a capa primeiro, sem a montagem dos grupos, sem repetir, JPG/PNG/WEBP públicas, até 30
  SELECT jsonb_agg(x.url ORDER BY x.n) INTO v_fotos
    FROM (SELECT y.url, min(y.n) AS n
            FROM (SELECT f.url, row_number() OVER (ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id) AS n
                    FROM imovel_fotos f
                   WHERE f.codigo = p_codigo AND NOT coalesce(f.e_mosaico, false)
                     AND f.url ~* '^https://' AND split_part(f.url, '?', 1) ~* '\.(jpe?g|png|webp)$') y
           GROUP BY y.url ORDER BY 2 LIMIT 30) x;
  IF v_fotos IS NULL THEN v_falta := v_falta || 'sem foto (JPG, PNG ou WEBP)'::text; END IF;

  IF v_falta <> '{}' THEN
    RETURN jsonb_build_object('ok', false, 'falta', to_jsonb(v_falta));
  END IF;

  SELECT * INTO cf FROM condominio_ficha c WHERE c.condominio_id = i.condo_id;

  -- as áreas: a característica do imóvel é privativa; a que não casa lá e o que é do condomínio vão para comum
  v_priv := cnm_areas(i.caracteristicas, 'privativa');
  SELECT coalesce(array_agg(t ORDER BY n), '{}') INTO v_resto
    FROM unnest(coalesce(i.caracteristicas, '{}')) WITH ORDINALITY u(t, n)
   WHERE cardinality(cnm_areas(ARRAY[t], 'privativa')) = 0;
  v_comum := cnm_areas(v_resto || coalesce(cf.lazer, '{}') || coalesce(cf.seguranca, '{}') || coalesce(cf.comodidades, '{}'), 'comum');
  -- a mobília (campo próprio do cadastro)
  v_mob := lower(nay_sem_acento(coalesce(i.mobilia, '')));
  IF v_mob ~ '^mobiliado' AND NOT 'Mobiliado' = ANY (v_priv) THEN v_priv := v_priv || 'Mobiliado'::text; END IF;
  IF v_mob ~ 'modulad' AND NOT 'Armário(s) planejado(s)' = ANY (v_priv) THEN v_priv := v_priv || 'Armário(s) planejado(s)'::text; END IF;
  IF v_mob ~ '(\mar\M|climatizad)' AND NOT 'Ar Condicionado' = ANY (v_priv) THEN v_priv := v_priv || 'Ar Condicionado'::text; END IF;
  -- regra do portal: piscina não pode estar nas duas
  IF 'Piscina' = ANY (v_comum) THEN v_priv := array_remove(v_priv, 'Piscina'); END IF;
  v_pet := 'Aceita Pet' = ANY (v_priv) OR 'Aceita pet' = ANY (v_comum) OR 'Permitido pets' = ANY (v_comum);

  -- o CEP: o do imóvel; sem ele, o do condomínio (não é obrigatório no portal)
  v_cep := regexp_replace(coalesce(i.cep, ''), '\D', '', 'g');
  IF v_cep !~ '^\d{8}$' THEN v_cep := regexp_replace(coalesce(cf.cep, ''), '\D', '', 'g'); END IF;
  IF v_cep !~ '^\d{8}$' THEN v_cep := NULL; END IF;

  -- o título (até 100): "Apartamento com 3 quartos à venda no Kopenhagen, Ponta Negra"
  v_cond := nay_condominio_de_verdade(i.tipo, i.condominio_nome);
  v_neg := CASE WHEN v_venda IS NOT NULL AND v_aluga IS NOT NULL THEN ' à venda ou para alugar'
                WHEN v_venda IS NOT NULL THEN ' à venda' ELSE ' para alugar' END;
  v_tit := v_rot
    || CASE WHEN v_fin = 'RE' AND v_rot !~ '^(Terreno|Sítio)' AND coalesce(i.quartos, 0) > 0
            THEN ' com ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
    || v_neg
    || CASE WHEN v_cond IS NOT NULL THEN ' no ' || v_cond ELSE ' em ' || btrim(i.bairro) END;
  IF v_cond IS NOT NULL AND length(v_tit || ', ' || btrim(i.bairro)) <= 100 THEN v_tit := v_tit || ', ' || btrim(i.bairro); END IF;
  IF length(v_tit) > 100 THEN v_tit := btrim(regexp_replace(left(v_tit, 100), '\s+\S*$', '')); END IF;

  -- a descrição: a mesma do anúncio da OLX (o texto do cadastro e a ficha em linhas), até 3000
  v_desc := olx_corpo_do_anuncio(p_codigo, CASE WHEN v_venda IS NOT NULL THEN 'venda' ELSE 'locacao' END);
  IF length(v_desc) > 3000 THEN v_desc := btrim(regexp_replace(left(v_desc, 3000), '\s+\S*$', '')); END IF;

  RETURN jsonb_build_object('ok', true, 'falta', '[]'::jsonb, 'imovel', jsonb_build_object(
    'referencia', p_codigo::text,
    'codigo_cliente', p_codigo::text,
    'link_cliente', 'https://imobeasy.online/imovel/' || p_codigo,
    'titulo', v_tit,
    'transacao', CASE WHEN v_venda IS NOT NULL THEN 'V' ELSE 'L' END,
    'transacao2', CASE WHEN v_venda IS NOT NULL AND v_aluga IS NOT NULL THEN 'L' END,
    'finalidade', v_fin,
    'finalidade2', NULL,
    'destaque', 0,
    'tipo', v_tipo,
    'tipo2', NULL,
    'valor', coalesce(v_venda, v_aluga),
    'valor_locacao', CASE WHEN v_venda IS NOT NULL THEN v_aluga END,
    'valor_iptu', nullif(coalesce(i.iptu, 0), 0),
    'valor_condominio', nullif(coalesce(i.taxa_condominio, 0), 0),
    'area_total', nullif(coalesce(i.area_total, 0), 0),
    'area_util', nullif(coalesce(i.area_util, 0), 0),
    'conservacao', NULL,
    'quartos', CASE WHEN i.quartos >= 0 THEN i.quartos END,
    'suites', CASE WHEN i.suites >= 0 THEN i.suites END,
    'garagem', CASE WHEN i.vagas >= 0 THEN i.vagas END,
    'banheiro', CASE WHEN i.banheiros >= 0 THEN i.banheiros END,
    'aceita_pet', CASE WHEN v_pet THEN 1 ELSE 0 END,
    'estado', CASE WHEN upper(btrim(coalesce(i.estado, ''))) ~ '^[A-Z]{2}$' THEN upper(btrim(i.estado)) ELSE 'AM' END,
    'cidade', coalesce(nullif(btrim(coalesce(i.cidade, '')), ''), 'Manaus'),
    'bairro', btrim(i.bairro),
    'cep', v_cep,
    -- o endereço vai para o portal achar o lugar no mapa, mas não aparece no anúncio (esconder = 1)
    'endereco', left(nullif(btrim(coalesce(i.logradouro, '')), ''), 200),
    'numero', NULL,
    'complemento', NULL,
    'esconder_endereco_imovel', 1,
    'descritivo', v_desc,
    'fotos', v_fotos,
    'periodo_locacao', CASE WHEN v_aluga IS NOT NULL THEN 1 END,
    'area_comum', to_jsonb(v_comum),
    'area_privativa', to_jsonb(v_priv)));
END
$function$;
