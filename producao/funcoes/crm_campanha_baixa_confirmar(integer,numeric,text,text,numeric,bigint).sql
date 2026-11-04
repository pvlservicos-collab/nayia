CREATE OR REPLACE FUNCTION public.crm_campanha_baixa_confirmar(p_codigo integer, p_valor_novo numeric, p_quem text, p_finalidade text DEFAULT NULL::text, p_valor_antes numeric DEFAULT NULL::numeric, p_contato bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  i imoveis;
  v_fin text;
  v_antes numeric;
  v_id bigint;
BEGIN
  IF btrim(coalesce(p_quem, '')) = '' THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga quem confirmou'); END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'imóvel não existe'); END IF;
  v_fin := coalesce(p_finalidade, CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) > 0 THEN NULL
                                       WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'locacao' ELSE 'venda' END);
  IF v_fin IS NULL OR v_fin NOT IN ('locacao', 'venda') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o imóvel tem venda e aluguel: diga a finalidade (locacao | venda)');
  END IF;
  -- o valor de antes: o dito, ou o do retrato da campanha (o cadastro pode já estar com o novo), ou o do cadastro
  v_antes := coalesce(p_valor_antes,
    (SELECT (e->>CASE WHEN v_fin = 'locacao' THEN 'valor_aluguel' ELSE 'valor_venda' END)::numeric
       FROM campanha_contato c, jsonb_array_elements(c.imoveis) e
      WHERE (e->>'codigo')::int = p_codigo AND (p_contato IS NULL OR c.id = p_contato)
      ORDER BY c.id DESC LIMIT 1),
    CASE WHEN v_fin = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END);
  IF v_antes IS NULL OR p_valor_novo IS NULL OR p_valor_novo >= v_antes THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o valor novo não é menor que o de antes (' || coalesce(campanha_dinheiro(v_antes), '?') || ')');
  END IF;
  IF p_valor_novo < v_antes * 0.5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'mais de 50% abaixo de ' || campanha_dinheiro(v_antes) || ': confira (erro de digitação?)');
  END IF;
  IF EXISTS (SELECT 1 FROM campanha_baixa b WHERE b.codigo = p_codigo AND b.finalidade = v_fin AND b.estado IN ('confirmada', 'avisando')) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'já há uma baixa aberta deste imóvel');
  END IF;
  INSERT INTO campanha_baixa (codigo, finalidade, valor_antes, valor_novo, contato, quem)
  VALUES (p_codigo, v_fin, v_antes, p_valor_novo, p_contato, btrim(p_quem)) RETURNING id INTO v_id;
  IF p_contato IS NOT NULL THEN
    INSERT INTO campanha_evento (contato, tipo, texto, dados)
    VALUES (p_contato, 'nota', 'baixa confirmada por ' || btrim(p_quem), jsonb_build_object('baixa', v_id, 'valor', p_valor_novo));
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'finalidade', v_fin, 'de', v_antes, 'para', p_valor_novo,
                            'cadastro_ja_mostra', CASE WHEN v_fin = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END <= p_valor_novo);
END;
$function$;
