CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer, p_negocio text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE i imoveis; v_tit text; v_ico text; v_mob text; v_l text[] := '{}';
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  v_ico := CASE WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN '🏠' ELSE '🏢' END;
  v_tit := CASE
    WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
      THEN nai_condominio_ok(i.condominio_nome) || coalesce(' — ' || nullif(i.bairro, ''), '')
    ELSE initcap(coalesce(nullif(i.tipo, ''), 'Imóvel')) || coalesce(' no bairro ' || nullif(i.bairro, ''), '') END;
  IF coalesce(i.quartos, 0) > 0 THEN
    v_l := v_l || ('• ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
                   CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END);
  END IF;
  -- VENDA NAO LEVA "/mes" (Tel, 22/09). Numa lista de venda sai so o preco de
  -- venda; numa de locacao, so o aluguel; sem saber, sai o que o imovel tiver.
  IF coalesce(p_negocio, 'ambos') IN ('venda', 'ambos') AND coalesce(i.valor_venda, 0) > 0 THEN
    v_l := v_l || ('• R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.'));
  END IF;
  IF coalesce(p_negocio, 'ambos') IN ('locacao', 'ambos') AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_l := v_l || ('• R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') || '/mês');
  END IF;
  v_mob := CASE
    WHEN lower(coalesce(i.mobilia, '')) ~ '^semi' THEN 'Semimobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN 'Mobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN 'Com ar-condicionado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'semi.?mobiliad' THEN 'Semimobiliado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'mobiliad' THEN 'Mobiliado' END;
  IF v_mob IS NOT NULL THEN v_l := v_l || ('• ' || v_mob); END IF;
  RETURN v_ico || ' *' || v_tit || ' #' || i.codigo || '*' ||
         CASE WHEN array_length(v_l, 1) > 0 THEN E'\n' || array_to_string(v_l, E'\n') ELSE '' END;
END;
$function$
;
