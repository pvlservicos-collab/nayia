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
  v_cat     text := nullif(btrim(coalesce(p->>'categoria', '')), '');
  v_neg     text := nullif(btrim(coalesce(p->>'negocio', '')), '');
  v_texto   text;
  v_gids    text[];      -- 415: os grupos marcados um a um
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

  -- A LISTA DE IMÓVEIS (285): nova (veio a categoria) ou a edição de uma vaga que já é de lista. O tipo da
  -- mensagem não muda na edição: lista continua lista, imóvel continua imóvel.
  IF (v_id IS NULL AND v_cat IS NOT NULL) OR v_atual.categoria IS NOT NULL THEN
    v_cat  := coalesce(v_cat, v_atual.categoria);
    v_neg  := coalesce(v_neg, v_atual.negocio);
    v_dest := coalesce(v_dest, v_atual.destino, 'parceiros');
    IF v_cat NOT IN ('apartamento', 'apartamento_via_publica', 'casa_condominio', 'casa_via_publica', 'sala', 'lote') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Escolha o tipo de imóvel da lista.');
    END IF;
    IF coalesce(v_neg, '') NOT IN ('locacao', 'venda') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Diga se a lista é de locação ou de venda.');
    END IF;
    IF v_dest NOT IN ('parceiros', 'easy', 'comercial') THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Destino da lista inválido.');
    END IF;
    -- o texto: a chave ausente não mexe no que está gravado (a tela antiga só mudava o horário)
    v_texto := CASE WHEN p ? 'texto_fixo' THEN nullif(btrim(coalesce(p->>'texto_fixo', '')), '') ELSE v_atual.texto_fixo END;
    IF v_texto IS NOT NULL THEN
      IF length(v_texto) > 20000 THEN
        RETURN jsonb_build_object('ok', false, 'erro', 'O texto ficou grande demais (o limite é de 20 mil letras).');
      END IF;
      -- a parede do publicador na hora do envio é pela linha "cod 1234": sem nenhum imóvel no ar, não há lista
      IF NOT EXISTS (SELECT 1 FROM regexp_matches(v_texto, '\mcod\.?\s*(\d{3,5})\M', 'gi') m
                       JOIN imoveis i ON i.codigo = m[1]::int
                      WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                        AND NOT coalesce(i.e_parceiro, false)) THEN
        RETURN jsonb_build_object('ok', false, 'erro',
          'O texto precisa ter pelo menos um imóvel que está no ar, escrito como na lista: "cod 1234".');
      END IF;
    ELSIF (SELECT quantos FROM nay_lista_de_imoveis(v_cat, v_neg)) = 0 AND v_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Hoje não há nenhum imóvel nessa lista: nada sairia.');
    END IF;
    BEGIN
      IF v_id IS NULL THEN
        INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, categoria, negocio, destino, texto_fixo)
        VALUES (v_hora, v_rec, CASE WHEN v_rec = 'semanal' THEN v_dias END, CASE WHEN v_rec = 'unica' THEN v_data END,
                v_cat, v_neg, v_dest, v_texto)
        RETURNING id INTO v_id;
      ELSE
        UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                         dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                         data_unica = CASE WHEN v_rec = 'unica' THEN v_data END,
                         categoria = v_cat, negocio = v_neg, destino = v_dest, texto_fixo = v_texto
         WHERE id = v_id;
      END IF;
    EXCEPTION WHEN unique_violation THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Já existe essa lista, nesse horário e para esse destino.');
    END;
    RETURN jsonb_build_object('ok', true, 'id', v_id);
  END IF;

  -- 415 (Pedro, 19/10: "não tem uma lista marcável para selecionar o grupo que quero mandar a mesma mensagem em
  -- vários"): os grupos marcados. Com eles, o destino por apelido sai (cada grupo marcado já é o destino).
  SELECT array_agg(DISTINCT x) INTO v_gids
    FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'grupos_ids') = 'array' THEN p->'grupos_ids' ELSE '[]'::jsonb END) x
   WHERE btrim(x) <> '';
  IF coalesce(cardinality(v_gids), 0) > 0 THEN
    IF EXISTS (SELECT 1 FROM unnest(v_gids) x
                WHERE NOT EXISTS (SELECT 1 FROM grupos g WHERE g.id_grupo = x AND g.ativo AND coalesce(g.apelido, '') <> 'lotado')) THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'Um dos grupos marcados não está mais ativo. Recarregue a página.');
    END IF;
    v_dest := NULL;
  END IF;

  -- o destino: um apelido de grupo que existe (vazio = cada imóvel vai aos grupos que aceitam o tipo e o valor dele)
  IF v_dest IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v_dest AND v_dest <> 'lotado') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Esse grupo de destino não existe.');
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
      INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, codigos, destino, grupos_ids)
      VALUES (v_hora, v_rec, CASE WHEN v_rec = 'semanal' THEN v_dias END, CASE WHEN v_rec = 'unica' THEN v_data END, v_cods, v_dest,
              CASE WHEN cardinality(v_gids) > 0 THEN v_gids END)
      RETURNING id INTO v_id;
    ELSE
      UPDATE vagas SET horario = v_hora, tipo_recorrencia = v_rec,
                       dias_semana = CASE WHEN v_rec = 'semanal' THEN v_dias END,
                       data_unica = CASE WHEN v_rec = 'unica' THEN v_data END,
                       codigos = v_cods, destino = v_dest, grupos_ids = CASE WHEN cardinality(v_gids) > 0 THEN v_gids END
       WHERE id = v_id;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Já existe uma mensagem com esses imóveis, nesse horário e para esses grupos.');
  END;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END;
$function$;
