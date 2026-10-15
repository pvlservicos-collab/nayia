CREATE OR REPLACE FUNCTION public.olx_anuncio_montar(p_codigo integer, p_negocio text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i         imoveis;
  cf        condominio_ficha;
  v_ad      text := 'IE' || p_codigo || CASE WHEN p_negocio = 'venda' THEN 'V' ELSE 'L' END;
  v_t       text;                      -- o tipo, sem acento e minúsculo
  v_cat     int;
  v_tipo    text;                      -- o tipo como vai no título
  v_preco   numeric;
  v_cep     text;
  v_fone    text := regexp_replace(coalesce(olx_cfg('telefone'), ''), '\D', '', 'g');
  v_condo   text;
  v_onde    text := '';
  v_titulo  text;
  v_corpo   text;
  v_linhas  text[] := '{}';
  v_fotos   jsonb;
  v_params  jsonb := '{}'::jsonb;
  v_im      text[];                    -- características do imóvel
  v_co      text[] := '{}';            -- do condomínio (lazer, segurança, comodidades)
  v_f       text[] := '{}';
  v_c       text[] := '{}';
  v_area    numeric;
  v_falta   text[] := '{}';
  v_barrado text;
  v_an      jsonb;
BEGIN
  IF p_negocio NOT IN ('venda', 'locacao') THEN
    RETURN jsonb_build_object('ok', false, 'barrado', 'negócio desconhecido', 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'barrado', 'o imóvel não está no cadastro', 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;
  v_preco := CASE WHEN p_negocio = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END;

  -- QUEM NÃO PODE IR (e sai, se estiver lá)
  v_barrado := CASE
    WHEN coalesce(i.e_parceiro, false) THEN 'imóvel de parceiro'
    WHEN i.status IS DISTINCT FROM 'Disponível' OR NOT coalesce(i.disponivel, false) THEN 'não está Disponível (' || coalesce(i.status, 'sem situação') || ')'
    WHEN coalesce(i.bloqueado, false) THEN 'bloqueado'
    WHEN NOT coalesce(i.publicado_no_site, false) THEN 'fora do nosso site'
    WHEN coalesce(v_preco, 0) <= 0 THEN 'sem valor de ' || CASE WHEN p_negocio = 'venda' THEN 'venda' ELSE 'aluguel' END
  END;
  IF v_barrado IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'barrado', v_barrado, 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;

  SELECT * INTO cf FROM condominio_ficha c WHERE c.condominio_id = i.condo_id;
  v_t  := lower(nay_sem_acento(coalesce(i.tipo, '')));
  v_im := coalesce(i.caracteristicas, '{}');
  IF cf.id IS NOT NULL THEN v_co := cf.lazer || cf.seguranca || cf.comodidades; END IF;

  -- a categoria e o nome do tipo
  IF v_t ~ '^(apartamento|cobertura|flat|kitnet|kitinete|loft|studio)' THEN
    v_cat := 1020;
    v_tipo := CASE WHEN v_t ~ '^cobertura' OR coalesce(i.cobertura, false) THEN 'Cobertura' WHEN v_t ~ '^flat' THEN 'Flat'
                   WHEN v_t ~ '^kit' THEN 'Kitnet' WHEN v_t ~ '^loft' THEN 'Loft' WHEN v_t ~ '^studio' THEN 'Studio' ELSE 'Apartamento' END;
  ELSIF v_t ~ '^(casa|sobrado)' THEN
    v_cat := 1040;
    v_tipo := CASE WHEN v_t ~ 'condominio' THEN 'Casa em condomínio' ELSE 'Casa' END;
  ELSIF v_t ~ '^(lote|terreno|area|sitio|chacara|fazenda)' THEN
    v_cat := 1100;
    v_tipo := CASE WHEN v_t ~ '^sitio' THEN 'Sítio' WHEN v_t ~ '^chacara' THEN 'Chácara' WHEN v_t ~ '^fazenda' THEN 'Fazenda'
                   WHEN v_t ~ 'condominio' THEN 'Lote em condomínio' WHEN v_t ~ '^terreno' THEN 'Terreno' ELSE 'Lote' END;
  ELSIF v_t ~ '^(sala|andar|loja|ponto|galpao|deposito|predio|comercial)' THEN
    v_cat := 1120;
    v_tipo := CASE WHEN v_t ~ '^(sala|andar)' THEN 'Sala comercial' WHEN v_t ~ '^(loja|ponto)' THEN 'Loja'
                   WHEN v_t ~ '^(galpao|deposito)' THEN 'Galpão' WHEN v_t ~ '^predio' THEN 'Prédio comercial' ELSE 'Imóvel comercial' END;
  ELSE
    v_falta := array_append(v_falta, 'tipo de imóvel sem categoria na OLX (' || coalesce(nullif(btrim(i.tipo), ''), 'sem tipo') || ')');
  END IF;

  -- o valor tem de ser crível (um zero a mais ou a menos vira anúncio errado no ar)
  IF p_negocio = 'venda' AND v_preco < 20000 THEN v_falta := array_append(v_falta, 'valor de venda baixo demais para ser de venda (' || v_preco::bigint || ')'); END IF;
  IF p_negocio = 'locacao' AND v_preco NOT BETWEEN 300 AND 200000 THEN v_falta := array_append(v_falta, 'valor de aluguel fora do esperado (' || v_preco::bigint || ')'); END IF;

  -- o CEP: o do imóvel; sem ele, o do condomínio
  v_cep := regexp_replace(coalesce(i.cep, ''), '\D', '', 'g');
  IF v_cep !~ '^\d{8}$' THEN v_cep := regexp_replace(coalesce(cf.cep, ''), '\D', '', 'g'); END IF;
  IF v_cep !~ '^\d{8}$' THEN v_falta := array_append(v_falta, 'sem CEP (nem no imóvel nem no condomínio)'); END IF;

  IF length(v_fone) NOT BETWEEN 10 AND 11 THEN v_falta := array_append(v_falta, 'o telefone do anúncio (chave telefone) não tem 10 ou 11 dígitos'); END IF;

  -- as fotos: a capa primeiro, sem a montagem dos grupos, sem repetir, só JPG/PNG/GIF (a OLX não aceita webp), até 20
  SELECT jsonb_agg(x.url ORDER BY x.n) INTO v_fotos
    FROM (SELECT y.url, min(y.n) AS n
            FROM (SELECT f.url, row_number() OVER (ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id) AS n
                    FROM imovel_fotos f
                   WHERE f.codigo = p_codigo AND NOT coalesce(f.e_mosaico, false)
                     AND f.url ~* '^https://' AND split_part(f.url, '?', 1) ~* '\.(jpe?g|png|gif)$') y
           GROUP BY y.url
           ORDER BY 2
           LIMIT 20) x;
  IF v_fotos IS NULL THEN v_falta := array_append(v_falta, 'sem foto que a OLX aceite (JPG, PNG ou GIF)'); END IF;

  -- os parâmetros da categoria. O que não sabemos NÃO vai: opcional vazio ou zero derruba a importação
  v_area := CASE WHEN v_cat = 1100 THEN coalesce(nullif(i.area_total, 0), nullif(i.area_util, 0)) ELSE coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) END;
  IF v_area >= 1 THEN v_params := v_params || jsonb_build_object('size', round(v_area)::bigint::text); END IF;
  IF coalesce(i.taxa_condominio, 0) >= 1 AND i.taxa_condominio_em IS NOT NULL THEN
    v_params := v_params || jsonb_build_object('condominio', round(i.taxa_condominio)::bigint::text);
  END IF;
  IF v_cat IN (1020, 1040, 1120) AND i.vagas IS NOT NULL AND i.vagas >= 0 THEN
    v_params := v_params || jsonb_build_object('garage_spaces', least(i.vagas, 5)::text);
  END IF;
  IF v_cat IN (1020, 1040) THEN
    IF i.quartos IS NULL OR i.quartos < 0 THEN v_falta := array_append(v_falta, 'sem número de quartos');
    ELSE v_params := v_params || jsonb_build_object('rooms', least(i.quartos, 5)::text); END IF;
    IF coalesce(i.banheiros, 0) >= 1 THEN v_params := v_params || jsonb_build_object('bathrooms', least(i.banheiros, 5)::text); END IF;
  END IF;

  IF v_cat = 1020 THEN
    v_params := v_params || jsonb_build_object('apartment_type',
      CASE v_tipo WHEN 'Cobertura' THEN '2' WHEN 'Kitnet' THEN '4' WHEN 'Loft' THEN '5' WHEN 'Studio' THEN '4' ELSE '1' END);
    IF olx_tem(v_im, '(ar.condicionado|climatizad)') OR lower(coalesce(i.mobilia, '')) ~ '(climatizad| ar\M)' THEN v_f := array_append(v_f, '1'); END IF;
    IF olx_tem(v_im, 'armarios? no quarto') THEN v_f := array_append(v_f, '3'); END IF;
    IF olx_tem(v_im, '^varanda') THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_im, 'area de servico') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_im, '(quarto de servico|dependencia de empregada)') THEN v_f := array_append(v_f, '7'); END IF;
    IF olx_tem(v_im, '^piscina') THEN v_f := array_append(v_f, '8'); END IF;
    IF olx_tem(v_im, 'armarios? na cozinha') THEN v_f := array_append(v_f, '11'); END IF;
    IF olx_tem(v_im, '^mobiliado') OR lower(coalesce(i.mobilia, '')) ~ '^mobiliado' THEN v_f := array_append(v_f, '12'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('apartment_features', to_jsonb(v_f)); END IF;
    IF olx_tem(v_co, 'condominio fechado') THEN v_c := array_append(v_c, '1'); END IF;
    IF olx_tem(v_co || v_im, '^elevador') OR lower(coalesce(cf.elevador, '')) ~ '^sim' THEN v_c := array_append(v_c, '2'); END IF;
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_c := array_append(v_c, '3'); END IF;
    IF olx_tem(v_co, '^(portaria|guarita)') THEN v_c := array_append(v_c, '4'); END IF;
    IF olx_tem(v_im || v_co, '(aceita pet|permitido animais)') THEN v_c := array_append(v_c, '5'); END IF;
    IF olx_tem(v_co, '(^academia|^fitness)') THEN v_c := array_append(v_c, '6'); END IF;
    IF olx_tem(v_co, '^piscina') THEN v_c := array_append(v_c, '7'); END IF;
    IF olx_tem(v_co, '^salao de festas') THEN v_c := array_append(v_c, '8'); END IF;
    IF v_c <> '{}' THEN v_params := v_params || jsonb_build_object('apartment_complex_features', to_jsonb(v_c)); END IF;
  ELSIF v_cat = 1040 THEN
    v_params := v_params || jsonb_build_object('home_type', CASE WHEN v_tipo = 'Casa em condomínio' THEN '3' ELSE '1' END);
    IF olx_tem(v_im, '(ar.condicionado|climatizad)') OR lower(coalesce(i.mobilia, '')) ~ '(climatizad| ar\M)' THEN v_f := array_append(v_f, '1'); END IF;
    IF olx_tem(v_im, '^piscina') THEN v_f := array_append(v_f, '2'); END IF;
    IF olx_tem(v_im, 'armarios? no quarto') THEN v_f := array_append(v_f, '3'); END IF;
    IF olx_tem(v_im, '^varanda') THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_im, 'area de servico') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_im, '^churrasqueira') THEN v_f := array_append(v_f, '6'); END IF;
    IF olx_tem(v_im, '(quarto de servico|dependencia de empregada)') THEN v_f := array_append(v_f, '7'); END IF;
    IF olx_tem(v_im, 'armarios? na cozinha') THEN v_f := array_append(v_f, '9'); END IF;
    IF olx_tem(v_im, '^mobiliado') OR lower(coalesce(i.mobilia, '')) ~ '^mobiliado' THEN v_f := array_append(v_f, '10'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('home_features', to_jsonb(v_f)); END IF;
    IF v_tipo = 'Casa em condomínio' THEN v_c := array_append(v_c, '1'); END IF;
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_c := array_append(v_c, '2'); END IF;
    IF olx_tem(v_im, '(^murado|area murada)') THEN v_c := array_append(v_c, '3'); END IF;
    IF olx_tem(v_im || v_co, '(aceita pet|permitido animais)') THEN v_c := array_append(v_c, '4'); END IF;
    IF olx_tem(v_co, '(^academia|^fitness)') THEN v_c := array_append(v_c, '6'); END IF;
    IF olx_tem(v_co, '^piscina') THEN v_c := array_append(v_c, '9'); END IF;
    IF v_c <> '{}' THEN v_params := v_params || jsonb_build_object('home_complex_features', to_jsonb(v_c)); END IF;
  ELSIF v_cat = 1100 THEN
    v_params := v_params || jsonb_build_object('re_land_type',
      CASE WHEN v_tipo IN ('Sítio', 'Chácara') THEN '2' WHEN v_tipo = 'Fazenda' THEN '3' ELSE '1' END);
  ELSIF v_cat = 1120 THEN
    v_params := v_params || jsonb_build_object('commercial_type',
      CASE v_tipo WHEN 'Sala comercial' THEN '1' WHEN 'Galpão' THEN '2' WHEN 'Loja' THEN '6' ELSE '7' END);
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_f := array_append(v_f, '2'); END IF;
    IF olx_tem(v_co || v_im, '^elevador') OR lower(coalesce(cf.elevador, '')) ~ '^sim' THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_co, '^(portaria|guarita)') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_co, 'acesso para deficientes') THEN v_f := array_append(v_f, '6'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('commercial_features', to_jsonb(v_f)); END IF;
  END IF;

  -- o título (até 90): "Apartamento com 3 quartos à venda no Kopenhagen, Ponta Negra"
  v_condo := nullif(btrim(coalesce(i.condominio_nome, '')), '');
  IF v_condo IN ('—', '-', '–') OR v_condo ~* 'n[aã]o identificad'
     OR lower(nay_sem_acento(coalesce(v_condo, ''))) ~ '^(casa|predio|lote|terreno|sala|loja|apartamento|galpao)( em via publica| comercial)?$'
     OR EXISTS (SELECT 1 FROM (SELECT DISTINCT x.tipo FROM imoveis x WHERE x.tipo IS NOT NULL) d
                 WHERE lower(nay_sem_acento(d.tipo)) = lower(nay_sem_acento(coalesce(v_condo, '')))) THEN
    v_condo := NULL;      -- "condomínio" que é só o nome do tipo ("Loja/Ponto", "Casa"; 356): cita o bairro
  END IF;
  v_onde := CASE WHEN v_condo IS NOT NULL THEN ' no ' || v_condo WHEN nullif(btrim(coalesce(i.bairro, '')), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END;
  v_titulo := coalesce(v_tipo, 'Imóvel')
    || CASE WHEN v_cat IN (1020, 1040) AND coalesce(i.quartos, 0) > 0 THEN ' com ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
    || CASE WHEN p_negocio = 'venda' THEN ' à venda' ELSE ' para alugar' END
    || v_onde;
  IF v_condo IS NOT NULL AND nullif(btrim(coalesce(i.bairro, '')), '') IS NOT NULL
     AND length(v_titulo || ', ' || btrim(i.bairro)) <= 90 THEN
    v_titulo := v_titulo || ', ' || btrim(i.bairro);
  END IF;
  IF length(v_titulo) > 90 THEN v_titulo := btrim(regexp_replace(left(v_titulo, 90), '\s+\S*$', '')); END IF;

  -- a descrição: a do cadastro (limpa) e, embaixo, a ficha em linhas
  v_corpo := olx_corpo_do_anuncio(p_codigo, p_negocio);

  IF v_falta <> '{}' THEN
    RETURN jsonb_build_object('ok', false, 'barrado', NULL, 'falta', to_jsonb(v_falta), 'ad_id', v_ad, 'titulo', v_titulo,
                              'preco', round(v_preco)::bigint, 'fotos', coalesce(jsonb_array_length(v_fotos), 0));
  END IF;

  v_an := jsonb_build_object(
    'id', v_ad, 'operation', 'insert', 'category', v_cat, 'subject', v_titulo, 'body', v_corpo,
    'phone', v_fone::bigint, 'type', CASE WHEN p_negocio = 'venda' THEN 's' ELSE 'u' END,
    'price', round(v_preco)::bigint, 'zipcode', v_cep,
    'phone_hidden', coalesce(olx_cfg('mostrar_telefone'), 'nao') <> 'sim',
    'params', v_params, 'images', v_fotos);
  RETURN jsonb_build_object('ok', true, 'barrado', NULL, 'falta', '[]'::jsonb, 'ad_id', v_ad, 'anuncio', v_an,
                            'hash', md5(v_an::text), 'titulo', v_titulo, 'preco', round(v_preco)::bigint,
                            'fotos', jsonb_array_length(v_fotos));
END
$function$;
