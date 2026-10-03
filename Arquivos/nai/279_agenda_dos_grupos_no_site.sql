-- 279 (03/10/2026): A AGENDA DOS GRUPOS NO ADMIN DO SITE.
--
-- Pedro, 03/10: "uma aba Grupos no site normal, onde eu vou criar e agendar mensagens, e o conteúdo da
-- mensagem vou preencher com os imóveis... no formato de uma agenda geral lá em cima, e eu podendo filtrar
-- por grupo; quero adicionar, excluir, editar, metrificar a mensagem; as métricas são quantas pessoas
-- chegaram nas próximas 6 horas que enviei".
--
-- NÃO É UM AGENDADOR NOVO. A grade do publicador (`vagas`) já é isso: horário, repetição (diária, semanal,
-- única), os imóveis e o destino (apelido do grupo; vazio = cada imóvel vai aos grupos que aceitam o tipo e
-- o valor dele). O cron disparar_grade.sh a executa a cada minuto e grava cada post em `envios`
-- (destino 'grupo', grupo_nome, código, message_id). Esta migração só dá ao site o jeito de ver, criar,
-- editar e excluir a grade, e a métrica de cada envio:
--
--   site_grade_agenda(de, ate)   as ocorrências do período (cada vaga em cada dia), com os imóveis, os grupos
--                                previstos e, das que já passaram, para onde foi e quem chegou em 6 h
--   site_grade_salvar(json)      cria ou edita uma vaga de imóveis (as paredes: imóvel no ar, nunca de parceiro)
--   site_grade_excluir(id)       apaga a vaga, guardando uma cópia em privado.grade_excluida
--   site_grade_opcoes()          os grupos e os destinos possíveis
--
-- A MÉTRICA ("quantas pessoas chegaram nas 6 h seguintes"), por ocorrência que já passou:
--   pessoas      quem escreveu ao número da Parceria nas 6 h depois do horário (sem equipe e sem teste)
--   novos        dessas, quem falou com a Nay pela primeira vez nessa janela
--   pelo_imovel  dessas, quem citou o post do grupo ou escreveu o código de um dos imóveis dele
-- Posts no mesmo horário dividem as mesmas "pessoas"; o "pelo_imovel" é o que separa um do outro.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grade_excluida (
  id           bigserial PRIMARY KEY,
  vaga         jsonb NOT NULL,
  excluida_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.grade_excluida IS '279: cópia de cada vaga da grade apagada pelo site (para desfazer à mão).';

CREATE OR REPLACE FUNCTION public.site_grade_opcoes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'grupos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id_grupo, 'nome', g.nome, 'apelido', g.apelido,
                                  'ativo', g.ativo, 'venda', g.aceita_venda, 'locacao', g.aceita_locacao,
                                  'so_condominio', g.so_condominio, 'so_comercial', g.so_comercial)
                                ORDER BY g.nome) FROM grupos g), '[]'::jsonb),
    'destinos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', d.apelido, 'grupos', d.nomes) ORDER BY d.apelido)
                            FROM (SELECT g.apelido, array_agg(g.nome ORDER BY g.nome) AS nomes FROM grupos g
                                   WHERE g.ativo AND coalesce(g.apelido, '') NOT IN ('', 'lotado') GROUP BY g.apelido) d), '[]'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.site_grade_agenda(p_de date, p_ate date DEFAULT NULL)
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
           CASE WHEN EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
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
  ), mesma_hora AS (   -- os códigos de imóvel postados no mesmo horário (para a vaga de LISTA não tomar os posts deles)
    SELECT oc.quando, array_agg(DISTINCT c) AS codigos
      FROM oc JOIN vagas v ON v.id = oc.vaga_id, unnest(v.codigos) c
     GROUP BY oc.quando
  ), env AS (
    SELECT oc.vaga_id, oc.quando,
           array_agg(DISTINCT e.grupo_nome) FILTER (WHERE e.grupo_nome IS NOT NULL) AS grupos,
           array_agg(DISTINCT e.message_id) FILTER (WHERE e.message_id IS NOT NULL) AS ids,
           array_agg(DISTINCT e.codigo) AS codigos,
           count(*) AS posts
      FROM oc JOIN vagas v ON v.id = oc.vaga_id
      JOIN envios e ON e.destino = 'grupo'
                   AND e.enviado_em >= oc.quando - interval '1 minute' AND e.enviado_em < oc.quando + interval '90 minutes'
                   AND (CASE WHEN cardinality(v.codigos) > 0 THEN e.codigo = ANY (v.codigos)
                             ELSE NOT (e.codigo = ANY (coalesce((SELECT mh.codigos FROM mesma_hora mh WHERE mh.quando = oc.quando), '{}'::text[]))) END)
     WHERE oc.quando <= now()
     GROUP BY oc.vaga_id, oc.quando
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
                                              OR s.texto ~ ('\m(' || array_to_string(env.codigos, '|') || ')\M')) AS pelo_imovel
      FROM env
      LEFT JOIN msgs s ON s.criada_em >= env.quando AND s.criada_em < env.quando + interval '6 hours'
     GROUP BY env.vaga_id, env.quando
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate, 'agora', now(),
    'vagas', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', vg.id, 'horario', to_char(vg.horario, 'HH24:MI'), 'recorrencia', vg.tipo_recorrencia,
        'dias', to_jsonb(vg.dias_semana), 'data', vg.data_unica, 'destino', vg.destino,
        'categoria', vg.categoria, 'negocio', vg.negocio, 'criada_em', vg.criado_em,
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

CREATE OR REPLACE FUNCTION public.site_grade_excluir(p_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r vagas%ROWTYPE;
BEGIN
  DELETE FROM vagas WHERE id = p_id RETURNING * INTO r;
  IF r.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'Essa mensagem não existe mais.'); END IF;
  INSERT INTO privado.grade_excluida (vaga) VALUES (to_jsonb(r));
  RETURN jsonb_build_object('ok', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.site_grade_opcoes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_grade_agenda(date, date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_grade_salvar(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_grade_excluir(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_grade_opcoes() TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_agenda(date, date) TO nay_site_escrita, nay_site_leitura;
GRANT EXECUTE ON FUNCTION public.site_grade_salvar(jsonb) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_grade_excluir(integer) TO nay_site_escrita;

COMMIT;
