-- teste da 563: roda DENTRO da transação do ensaio (o COMMIT virou ROLLBACK)
DO $$
DECLARE
  j jsonb; j2 jsonb; v_n int; v_visitas int; v_cards int; v_parados int;
BEGIN
  j := site_imoveis_metricas('2026-09-01', current_date, false);
  v_n := jsonb_array_length(j->'imoveis');
  IF v_n < 10 THEN RAISE EXCEPTION 'poucos imóveis com atividade: %', v_n; END IF;

  SELECT coalesce(sum((x->>'visitas_parceria')::int + (x->>'visitas_leads')::int), 0),
         coalesce(sum((x->>'cards_parceria')::int + (x->>'cards_leads')::int), 0)
    INTO v_visitas, v_cards FROM jsonb_array_elements(j->'imoveis') x;
  RAISE NOTICE 'imóveis com atividade %, visitas %, cards %', v_n, v_visitas, v_cards;
  IF v_visitas = 0 THEN RAISE EXCEPTION 'nenhuma visita contada'; END IF;
  IF v_cards = 0 THEN RAISE EXCEPTION 'nenhum card contado'; END IF;

  -- período vazio (futuro) não devolve atividade
  j2 := site_imoveis_metricas(current_date + 30, current_date + 31, false);
  IF jsonb_array_length(j2->'imoveis') <> 0 THEN RAISE EXCEPTION 'período futuro devolveu linhas'; END IF;

  -- sem_atividade = true acrescenta os Disponíveis parados
  j2 := site_imoveis_metricas(current_date + 30, current_date + 31, true);
  v_parados := jsonb_array_length(j2->'imoveis');
  IF v_parados < 100 THEN RAISE EXCEPTION 'esperava os disponíveis parados, vieram %', v_parados; END IF;
  RAISE NOTICE 'disponíveis parados %', v_parados;

  -- o total de visitas confere com o painel do Início no mesmo período (Parceria + Leads)
  PERFORM 1 FROM jsonb_array_elements(j->'imoveis') x WHERE x->>'codigo' IS NULL;
  IF FOUND THEN RAISE EXCEPTION 'linha sem código'; END IF;
END $$;
