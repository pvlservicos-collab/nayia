-- 415: A MENSAGEM DOS GRUPOS VAI AOS GRUPOS MARCADOS (19/10/2026)
--
-- Pedro: "lá em Grupos, quando clica em Nova mensagem, não tem uma lista marcável para selecionar o grupo que quero
-- mandar a mesma mensagem em vários". Até aqui a mensagem de imóvel tinha um destino só: um apelido (12 dos 20 grupos
-- ativos não têm apelido) ou "todos os grupos que aceitam o imóvel". Agora `vagas.grupos_ids` guarda os grupos marcados;
-- o disparador (nay-publicador/disparar_grade.py) posta em cada um, com a regra de valor e tipo de cada grupo, e quem
-- tem apelido (Easy, Comercial, Alto Padrão) segue o caminho dele. A lista de imóveis (categoria) não muda.
-- Imóvel de parceiro continua recusado aqui (a parede do salvar) e no disparador (_postar_*: "parceria não sai").
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE vagas ADD COLUMN IF NOT EXISTS grupos_ids text[];
DROP INDEX IF EXISTS vagas_imovel_unica;
CREATE UNIQUE INDEX vagas_imovel_unica ON public.vagas USING btree (codigos, COALESCE(destino, ''::text), horario, tipo_recorrencia,
  COALESCE(dias_semana, '{}'::integer[]), COALESCE(grupos_ids, '{}'::text[]))
  WHERE ((categoria IS NULL) AND (COALESCE(array_length(codigos, 1), 0) > 0));

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

CREATE OR REPLACE FUNCTION public.site_grade_agenda(p_de date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_de  date := greatest(coalesce(p_de, current_date), current_date - 180);
  v_ate date := least(coalesce(p_ate, coalesce(p_de, current_date) + 6), greatest(coalesce(p_de, current_date), current_date - 180) + 62);
  v_ini timestamptz;
  v_fim timestamptz;
  v_teste text[] := nai_chaves_teste();
  v jsonb;
BEGIN
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := (v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus';
  WITH gerais AS (   -- sem destino: os grupos ativos que recebem post de imóvel (todas_fotos é outro caminho)
    SELECT array_agg(id_grupo) AS ids FROM grupos WHERE ativo AND NOT coalesce(todas_fotos, false)
  ), vg AS (
    SELECT v.*,
           CASE WHEN coalesce(cardinality(v.grupos_ids), 0) > 0 AND v.categoria IS NULL THEN   -- 415: os grupos marcados
                  (SELECT array_agg(g.id_grupo) FROM grupos g WHERE g.ativo AND g.id_grupo = ANY (v.grupos_ids))
                WHEN v.categoria IS NOT NULL THEN   -- a LISTA: os destinos do `_disparar_lista` do publicador
                  (SELECT array_agg(g.id_grupo) FROM grupos g
                    WHERE g.ativo
                      AND CASE v.destino WHEN 'easy' THEN g.apelido = 'easy'
                                         WHEN 'comercial' THEN g.apelido = 'comercial'
                                         ELSE NOT coalesce(g.todas_fotos, false)
                                              AND (CASE WHEN v.negocio = 'venda' THEN g.aceita_venda ELSE g.aceita_locacao END)
                                              AND NOT (coalesce(g.so_comercial, false) AND v.categoria <> 'sala') END)
                WHEN EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                THEN (SELECT array_agg(g.id_grupo) FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                ELSE (SELECT ids FROM gerais) END AS previstos
      FROM vagas v
  ), oc AS (
    SELECT vg.id AS vaga_id, ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') AS quando
      FROM vg, generate_series(v_de::timestamp, v_ate::timestamp, interval '1 day') d
     WHERE (vg.tipo_recorrencia = 'diaria'
            OR (vg.tipo_recorrencia = 'semanal' AND extract(dow FROM d)::int = ANY (vg.dias_semana))
            OR (vg.tipo_recorrencia = 'unica' AND d::date = vg.data_unica))
       AND ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') >= date_trunc('minute', vg.criado_em) - interval '1 minute'
  ), env AS (
    -- o post de IMÓVEL: o que o publicador gravou em `envios` na janela do horário
    SELECT oc.vaga_id, oc.quando,
           array_agg(DISTINCT e.grupo_nome) FILTER (WHERE e.grupo_nome IS NOT NULL) AS grupos,
           array_agg(DISTINCT e.message_id) FILTER (WHERE e.message_id IS NOT NULL) AS ids,
           array_agg(DISTINCT e.codigo) AS codigos,
           count(*) AS posts
      FROM oc JOIN vagas v ON v.id = oc.vaga_id AND v.categoria IS NULL AND cardinality(v.codigos) > 0
      JOIN envios e ON e.destino = 'grupo'
                   AND e.enviado_em >= oc.quando - interval '1 minute' AND e.enviado_em < oc.quando + interval '90 minutes'
                   AND e.codigo = ANY (v.codigos)
     WHERE oc.quando <= now()
     GROUP BY oc.vaga_id, oc.quando
    UNION ALL
    -- a LISTA (285): não grava em `envios`. Os grupos vêm de `lista_disparada`; os ids e os códigos, de
    -- `envios_lista_grupo` (desde a 281). Antes, a lista tomava os posts dos imóveis que saíam depois dela.
    SELECT oc.vaga_id, oc.quando, ld.grupos,
           (SELECT array_agg(DISTINCT x.message_id) FROM envios_lista_grupo x
             WHERE x.categoria = v.categoria AND x.negocio = v.negocio
               AND x.enviado_em >= ld.enviado_em - interval '1 minute' AND x.enviado_em < ld.enviado_em + interval '60 minutes'),
           (SELECT array_agg(DISTINCT x.codigo::text) FROM envios_lista_grupo x
             WHERE x.categoria = v.categoria AND x.negocio = v.negocio
               AND x.enviado_em >= ld.enviado_em - interval '1 minute' AND x.enviado_em < ld.enviado_em + interval '60 minutes'),
           cardinality(ld.grupos)::bigint
      FROM oc JOIN vagas v ON v.id = oc.vaga_id AND v.categoria IS NOT NULL
      JOIN LATERAL (SELECT l.grupos, l.enviado_em FROM lista_disparada l
                     WHERE l.categoria = v.categoria AND l.negocio = v.negocio AND l.destino = v.destino
                       AND l.enviado_em >= oc.quando - interval '1 minute' AND l.enviado_em < oc.quando + interval '30 minutes'
                       AND coalesce(cardinality(l.grupos), 0) > 0
                     ORDER BY l.enviado_em LIMIT 1) ld ON true
     WHERE oc.quando <= now()
  ), msgs0 AS MATERIALIZED (   -- o que chegou ao número da Parceria no período (+6 h)
    SELECT nai_chave(m.telefone) AS chave, m.criada_em, m.citado_id, m.texto
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em >= v_ini AND m.criada_em < v_fim + interval '6 hours'
  ), quem AS MATERIALIZED (    -- equipe e teste saem: uma conta por PESSOA, não por mensagem
    SELECT d.chave, k.criado_em AS desde,
           (d.chave = ANY (v_teste)) OR (k.id IS NOT NULL AND nai_e_da_equipe_contato(k.id)) AS fora
      FROM (SELECT DISTINCT chave FROM msgs0 WHERE chave IS NOT NULL) d
      LEFT JOIN nai_contato k ON k.chave = d.chave
  ), msgs AS MATERIALIZED (
    SELECT m.chave, m.criada_em, m.citado_id, m.texto, q.desde
      FROM msgs0 m JOIN quem q ON q.chave = m.chave
     WHERE NOT q.fora
  ), met AS (
    SELECT env.vaga_id, env.quando,
           count(DISTINCT s.chave) AS pessoas,
           count(DISTINCT s.chave) FILTER (WHERE s.desde >= env.quando) AS novos,
           count(DISTINCT s.chave) FILTER (WHERE s.citado_id = ANY (coalesce(env.ids, '{}'::text[]))
                                              OR (cardinality(coalesce(env.codigos, '{}'::text[])) > 0
                                                  AND s.texto ~ ('\m(' || array_to_string(env.codigos, '|') || ')\M'))) AS pelo_imovel
      FROM env
      LEFT JOIN msgs s ON s.criada_em >= env.quando AND s.criada_em < env.quando + interval '6 hours'
     GROUP BY env.vaga_id, env.quando
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate, 'agora', now(),
    'vagas', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', vg.id, 'horario', to_char(vg.horario, 'HH24:MI'), 'recorrencia', vg.tipo_recorrencia,
        'dias', to_jsonb(vg.dias_semana), 'data', vg.data_unica, 'destino', vg.destino, 'grupos_ids', to_jsonb(vg.grupos_ids),
        'categoria', vg.categoria, 'negocio', vg.negocio, 'texto_fixo', vg.texto_fixo, 'criada_em', vg.criado_em,
        'previstos', to_jsonb(vg.previstos),
        'imoveis', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                        'codigo', c.cod, 'existe', i.codigo IS NOT NULL,
                        'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo), 'bairro', i.bairro,
                        'venda', nullif(i.valor_venda, 0), 'aluguel', nullif(i.valor_aluguel, 0),
                        'no_ar', CASE WHEN i.codigo IS NULL THEN NULL
                                      ELSE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) END,
                        'parceiro', coalesce(i.e_parceiro, false),
                        'foto', (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo AND coalesce(f.url, '') <> ''
                                    AND NOT coalesce(f.e_mosaico, false)
                                  ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1)))
                        ORDER BY c.n)
                      FROM unnest(vg.codigos) WITH ORDINALITY c(cod, n)
                      LEFT JOIN imoveis i ON i.codigo::text = c.cod)))
        ORDER BY vg.horario, vg.id) FROM vg), '[]'::jsonb),
    'ocorrencias', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'vaga', oc.vaga_id, 'quando', oc.quando, 'passou', oc.quando <= now(),
        'janela_completa', oc.quando + interval '6 hours' <= now(),
        'posts', env.posts, 'grupos', to_jsonb(env.grupos),
        'pessoas', met.pessoas, 'novos', met.novos, 'pelo_imovel', met.pelo_imovel))
        ORDER BY oc.quando, oc.vaga_id)
      FROM oc
      LEFT JOIN env ON env.vaga_id = oc.vaga_id AND env.quando = oc.quando
      LEFT JOIN met ON met.vaga_id = oc.vaga_id AND met.quando = oc.quando), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;
COMMIT;
