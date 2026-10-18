CREATE OR REPLACE FUNCTION public.site_blog_metricas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH lim AS (SELECT coalesce(p_de, current_date - 29) AS de, coalesce(p_ate, current_date) AS ate),
  v AS (SELECT * FROM blog_visita, lim WHERE dia BETWEEN lim.de AND lim.ate)
  SELECT jsonb_build_object(
    'de', (SELECT de FROM lim), 'ate', (SELECT ate FROM lim),
    'dias', (SELECT jsonb_agg(d ORDER BY d) FROM generate_series((SELECT de FROM lim), (SELECT ate FROM lim), '1 day') d),
    'por_origem', (SELECT coalesce(jsonb_object_agg(o, s), '{}'::jsonb) FROM (
        SELECT o, jsonb_agg(coalesce(x.n, 0) ORDER BY d) AS s
          FROM unnest(ARRAY['google', 'ia', 'social', 'direto', 'outro', 'rastreador']) o
         CROSS JOIN generate_series((SELECT de FROM lim), (SELECT ate FROM lim), '1 day') d
          LEFT JOIN LATERAL (SELECT sum(n) AS n FROM v WHERE v.dia = d
                              AND CASE WHEN o = 'rastreador' THEN v.origem LIKE 'rastreador:%' ELSE v.origem = o END) x ON true
         GROUP BY o) q),
    'rastreadores', (SELECT coalesce(jsonb_object_agg(origem, n), '{}'::jsonb) FROM
        (SELECT replace(origem, 'rastreador:', '') AS origem, sum(n) AS n FROM v WHERE origem LIKE 'rastreador:%' GROUP BY 1) r),
    'total', (SELECT coalesce(sum(n), 0) FROM v WHERE origem NOT LIKE 'rastreador:%'),
    'artigos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'slug', a.slug, 'titulo', a.titulo, 'categoria', a.categoria,
                   'visitas', x.humanas, 'google', x.google, 'ia', x.ia, 'rastreadores', x.rastr) ORDER BY x.humanas DESC, x.rastr DESC), '[]'::jsonb)
      FROM blog_artigo a
      JOIN LATERAL (SELECT coalesce(sum(n) FILTER (WHERE origem NOT LIKE 'rastreador:%'), 0) AS humanas,
                           coalesce(sum(n) FILTER (WHERE origem = 'google'), 0) AS google,
                           coalesce(sum(n) FILTER (WHERE origem = 'ia'), 0) AS ia,
                           coalesce(sum(n) FILTER (WHERE origem LIKE 'rastreador:%'), 0) AS rastr
                      FROM v WHERE v.artigo_id = a.id) x ON true
     WHERE x.humanas > 0 OR x.rastr > 0))
$function$;
