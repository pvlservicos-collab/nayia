CREATE OR REPLACE FUNCTION public.nai_bloco_oferta(p_codigo integer, p_negocio text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
-- 222 (Pedro, 30/09): "uma lista mais bonitinha: nome do imóvel, endereço,
-- informações, preços, mobiliado sim ou não, quartos, condomínio ... quanto mais
-- informações melhor, mas sem encher muito texto". A primeira linha continua
-- "*Nome #1234*": é por ela que a busca e as paredes reconhecem um bloco.
DECLARE
  i imoveis; v_tit text; v_ico text; v_l text[] := '{}'; v_end text; v_inc text[]; v_inclui text;
  v_medidas text[] := '{}'; v_mob text; v_lazer text;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  v_ico := CASE WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN '🏠' ELSE '🏢' END;
  v_tit := coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''), initcap(coalesce(nullif(i.tipo, ''), 'Imóvel')));

  -- 📍 endereço · bairro
  v_end := concat_ws(', ', nullif(btrim(i.logradouro), ''), nullif(btrim(i.numero), ''));
  v_end := concat_ws(' · ', nullif(v_end, ''), nullif(btrim(i.bairro), ''));

  -- quartos · banheiros · vagas · área
  IF coalesce(i.quartos, 0) > 0 THEN
    v_medidas := v_medidas || (i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END
                 || CASE WHEN coalesce(i.suites, 0) > 0 THEN ' (' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte)' ELSE ' suítes)' END ELSE '' END);
  END IF;
  IF coalesce(i.banheiros, 0) > 0 THEN v_medidas := v_medidas || (i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END); END IF;
  IF coalesce(i.vagas, 0) > 0 THEN v_medidas := v_medidas || (i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga' ELSE ' vagas' END); END IF;
  IF coalesce(i.area_util, 0) > 0 THEN v_medidas := v_medidas || (trim(to_char(i.area_util, 'FM999990')) || ' m²'); END IF;
  IF array_length(v_medidas, 1) > 0 THEN v_l := v_l || ('• ' || array_to_string(v_medidas, ' · ')); END IF;

  -- o preço, com o que o aluguel inclui
  SELECT array_agg(n ORDER BY o) INTO v_inc FROM (VALUES
      (1, 'condomínio', 'condom'), (2, 'água', 'agua'), (3, 'gás', '\mgas'), (4, 'IPTU', 'iptu'), (5, 'energia', 'energia|luz')) x(o, n, rx)
   WHERE lower(unaccent(coalesce(i.extras->>'incluso no aluguel', ''))) ~ x.rx;
  v_inclui := CASE WHEN array_length(v_inc, 1) > 0 THEN ' (inclui ' || nai_lista_pt(v_inc) || ')'
                   WHEN coalesce(i.taxa_condominio, 0) > 0
                     THEN ' + condomínio R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.')
                   ELSE '' END;
  IF coalesce(p_negocio, 'ambos') IN ('locacao', 'ambos') AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_l := v_l || ('• Aluguel R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') || '/mês' || v_inclui);
  END IF;
  -- VENDA NAO LEVA "/mes" (Tel, 22/09)
  IF coalesce(p_negocio, 'ambos') IN ('venda', 'ambos') AND coalesce(i.valor_venda, 0) > 0 THEN
    v_l := v_l || ('• Venda R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.')
                   || CASE WHEN lower(coalesce(i.extras->>'aceita financiamento', '')) ~ '^s' THEN ' (aceita financiamento)' ELSE '' END);
  END IF;

  v_mob := nai_mobilia_da_lista(i.codigo);
  IF v_mob IS NOT NULL THEN v_l := v_l || ('• ' || v_mob); END IF;

  -- o lazer do condomínio que o anúncio antigo cita (até 4, sem "condomínio fechado")
  SELECT string_agg(x, ', ') INTO v_lazer FROM (
    SELECT DISTINCT ON (lower(x)) x FROM imovel_ficha f, unnest(f.caracteristicas_condominio) x
     WHERE f.codigo = i.codigo AND x !~* 'condom[ií]nio fechado|[aá]gua de po[cç]o|g[aá]s encanado'
     LIMIT 4) z;
  IF v_lazer IS NOT NULL THEN v_l := v_l || ('• Condomínio: ' || lower(v_lazer)); END IF;

  RETURN v_ico || ' *' || v_tit || ' #' || i.codigo || '*'
         || CASE WHEN nullif(v_end, '') IS NOT NULL THEN E'\n📍 ' || v_end ELSE '' END
         || CASE WHEN array_length(v_l, 1) > 0 THEN E'\n' || array_to_string(v_l, E'\n') ELSE '' END;
END;
$function$;
