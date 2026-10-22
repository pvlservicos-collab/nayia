CREATE OR REPLACE FUNCTION public.site_ia_modelos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH dia AS (SELECT (now() AT TIME ZONE 'America/Manaus')::date AS hoje),
  uso AS MATERIALIZED (
    SELECT u.no, u.modelo, u.em, u.custo_usd AS custo FROM privado.ia_uso u WHERE u.em > now() - interval '62 days'
    UNION ALL
    SELECT ia_no_do_core(t.etapa, t.modelo), t.modelo, t.criado_em,
           CASE WHEN t.saida ? 'custo' AND (t.saida->>'custo') ~ '^[0-9.eE+-]+$' THEN (t.saida->>'custo')::numeric END
      FROM core_trace t WHERE t.modelo IS NOT NULL AND t.criado_em > now() - interval '62 days'
  ),
  -- o n8n (a Nay velha) não registra tokens: as chamadas são os turnos em que ela respondeu (uma resposta 'turno' na
  -- nai_saida), no agente do papel e na secretária, que passa por todo turno
  velha AS MATERIALIZED (
    SELECT t.papel, t.criado_em FROM nai_turno t
     WHERE t.papel IN ('corretor', 'proprietario', 'motoboy') AND t.criado_em > now() - interval '62 days'
       AND EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = t.id AND s.papel_destino = 'turno' AND s.tipo = 'texto')
  ),
  n8n AS MATERIALIZED (
    SELECT CASE v.papel WHEN 'corretor' THEN 'n8n.corretor' WHEN 'proprietario' THEN 'n8n.proprietario'
                        ELSE 'n8n.fernando' END AS no, NULL::text AS modelo, v.criado_em AS em, NULL::numeric AS custo
      FROM velha v
    UNION ALL
    SELECT 'n8n.secretaria', NULL, v.criado_em, NULL FROM velha v
  ),
  tudo AS (SELECT * FROM uso UNION ALL SELECT * FROM n8n),
  per AS (
    SELECT x.no, x.modelo, x.custo,
           (x.em AT TIME ZONE 'America/Manaus')::date AS d, d0.hoje
      FROM tudo x CROSS JOIN dia d0
  ),
  por_no AS (
    SELECT no,
           jsonb_build_object(
             'hoje',  round(coalesce(sum(custo) FILTER (WHERE d = hoje), 0), 6),
             'ontem', round(coalesce(sum(custo) FILTER (WHERE d = hoje - 1), 0), 6),
             'd7',    round(coalesce(sum(custo) FILTER (WHERE d > hoje - 7), 0), 6),
             'd30',   round(coalesce(sum(custo) FILTER (WHERE d > hoje - 30), 0), 6),
             'mes',   round(coalesce(sum(custo) FILTER (WHERE date_trunc('month', d) = date_trunc('month', hoje)), 0), 6)) AS gasto,
           jsonb_build_object(
             'hoje',  count(*) FILTER (WHERE d = hoje),
             'ontem', count(*) FILTER (WHERE d = hoje - 1),
             'd7',    count(*) FILTER (WHERE d > hoje - 7),
             'd30',   count(*) FILTER (WHERE d > hoje - 30),
             'mes',   count(*) FILTER (WHERE date_trunc('month', d) = date_trunc('month', hoje))) AS chamadas,
           bool_or(custo IS NOT NULL) AS medido,
           (array_agg(modelo ORDER BY modelo) FILTER (WHERE modelo IS NOT NULL))[1] AS modelo_visto
      FROM per GROUP BY no
  ),
  serie AS (
    SELECT jsonb_agg(jsonb_build_object('dia', to_char(g.d, 'YYYY-MM-DD'),
                                        'custo', round(coalesce((SELECT sum(p.custo) FROM per p WHERE p.d = g.d), 0), 6))
                     ORDER BY g.d) AS s
      FROM dia, generate_series(dia.hoje - 29, dia.hoje, interval '1 day') AS gs(t), LATERAL (SELECT gs.t::date AS d) g
  )
  SELECT jsonb_build_object(
    'gerado_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD"T"HH24:MI:SS'),
    'nos', coalesce((SELECT jsonb_object_agg(no, jsonb_build_object('gasto', gasto, 'chamadas', chamadas, 'medido', medido,
                                                                     'modelo_visto', modelo_visto)) FROM por_no), '{}'::jsonb),
    'escolhidos', coalesce((SELECT jsonb_object_agg(m.no, jsonb_build_object('modelo', m.modelo, 'por', m.trocado_por,
                                                     'em', to_char(m.trocado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')))
                              FROM privado.ia_no_modelo m), '{}'::jsonb),
    'totais', jsonb_build_object(
       'hoje',  coalesce((SELECT round(sum(custo), 6) FROM per WHERE d = hoje), 0),
       'ontem', coalesce((SELECT round(sum(custo), 6) FROM per WHERE d = hoje - 1), 0),
       'd7',    coalesce((SELECT round(sum(custo), 6) FROM per WHERE d > hoje - 7), 0),
       'd30',   coalesce((SELECT round(sum(custo), 6) FROM per WHERE d > hoje - 30), 0),
       'mes',   coalesce((SELECT round(sum(custo), 6) FROM per WHERE date_trunc('month', d) = date_trunc('month', hoje)), 0)),
    'serie', (SELECT s FROM serie),
    'precos', coalesce((SELECT jsonb_object_agg(p.modelo, jsonb_build_object('entrada', p.entrada, 'entrada_cache', p.entrada_cache,
                                                  'saida', p.saida, 'por_minuto', p.por_minuto, 'fonte', p.fonte))
                          FROM privado.ia_preco p), '{}'::jsonb))
$function$;
