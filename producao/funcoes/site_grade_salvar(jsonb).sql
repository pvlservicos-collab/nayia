CREATE OR REPLACE FUNCTION public.site_grade_salvar(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id      int := nullif(p->>'id', '')::int;
  v_atual   vagas%ROWTYPE;
  v_hora    time;
  v_rec     text := coalesce(p->>'recorrencia', 'diaria');
  v_dias    int[];
  v_data    date;
  v_cods    text[];
  v_dest    text := nullif(btrim(coalesce(p->>'destino', '')), '');
  v_ruins   text[];
BEGIN
  IF v_id IS NOT NULL THEN
    SELECT * INTO v_atual FROM vagas WHERE id = v_id;
    IF v_atual.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Essa mensagem não existe mais.'); END IF;
  END IF;
  BEGIN
    v_hora := (p->>'horario')::time;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Horário inválido (use 07:30).');
  END;
  IF v_hora IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Diga o horário.'); END IF;
  IF v_rec NOT IN ('diaria', 'semanal', 'unica') THEN RETURN jsonb_build_object('ok', false, 'erro', 'Repetição inválida.'); END IF;
  IF v_rec = 'semanal' THEN
    SELECT array_agg(DISTINCT d ORDER BY d) INTO v_dias
      FROM jsonb_array_elements_text(coalesce(p->'dias', '[]'::jsonb)) x(t), LATERAL (SELECT x.t::int AS d) y
     WHERE y.d BETWEEN 0 AND 6;
    IF coalesce(cardinality(v_dias), 0) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha os dias da semana.'); END IF;
  ELSIF v_rec = 'unica' THEN
    BEGIN v_data := (p->>'data')::date; EXCEPTION WHEN OTHERS THEN v_data := NULL; END;
    IF v_data IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o dia.'); END IF;
    IF (v_data + v_hora) AT TIME ZONE 'America/Manaus' < now() THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Esse dia e horário já passaram.');
    END IF;
  END IF;

  -- o destino: um apelido de grupo que existe (vazio = cada imóvel vai aos grupos que aceitam o tipo e o valor dele)
  IF v_dest IS NOT NULL AND v_atual.categoria IS NULL
     AND NOT EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v_dest AND v_dest <> 'lotado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Esse grupo de destino não existe.');
  END IF;

  IF v_atual.categoria IS NOT NULL THEN
    -- vaga de LISTA (feita pelo comando do Tel): aqui só muda o quando
    UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                     dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                     data_unica = CASE WHEN v_rec = 'unica' THEN v_data END
     WHERE id = v_id;
    RETURN jsonb_build_object('ok', true, 'id', v_id);
  END IF;

  -- os imóveis: na ordem escritos, sem repetir, até 10
  SELECT array_agg(c ORDER BY n) INTO v_cods FROM (
    SELECT DISTINCT ON (c) c, n FROM (
      SELECT regexp_replace(x.t, '\D', '', 'g') AS c, x.n
        FROM jsonb_array_elements_text(coalesce(p->'codigos', '[]'::jsonb)) WITH ORDINALITY x(t, n)) y
     WHERE c <> '' ORDER BY c, n) z;
  IF coalesce(cardinality(v_cods), 0) = 0 THEN RETURN jsonb_build_object('ok', false, 'erro', 'Escolha pelo menos um imóvel.'); END IF;
  IF cardinality(v_cods) > 10 THEN RETURN jsonb_build_object('ok', false, 'erro', 'No máximo 10 imóveis por mensagem.'); END IF;
  -- as paredes do publicador: imóvel que existe, no ar, e nunca de parceiro (parceria não sai nos grupos)
  SELECT array_agg(c.cod || CASE WHEN i.codigo IS NULL THEN ' (não existe)'
                                 WHEN coalesce(i.e_parceiro, false) THEN ' (é de parceiro)'
                                 ELSE ' (não está no ar)' END)
    INTO v_ruins
    FROM unnest(v_cods) c(cod) LEFT JOIN imoveis i ON i.codigo::text = c.cod
   WHERE i.codigo IS NULL OR coalesce(i.e_parceiro, false)
      OR NOT nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site);
  IF v_ruins IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Não dá para agendar: ' || array_to_string(v_ruins, ', ') || '.');
  END IF;

  BEGIN
    IF v_id IS NULL THEN
      INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, codigos, destino)
      VALUES (v_hora, v_rec, CASE WHEN v_rec = 'semanal' THEN v_dias END, CASE WHEN v_rec = 'unica' THEN v_data END, v_cods, v_dest)
      RETURNING id INTO v_id;
    ELSE
      UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                       dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                       data_unica = CASE WHEN v_rec = 'unica' THEN v_data END,
                       codigos = v_cods, destino = v_dest
       WHERE id = v_id;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Já existe uma mensagem com esses imóveis, nesse horário e para esse destino.');
  END;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$function$;
