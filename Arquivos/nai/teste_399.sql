-- 399: o painel de métricas do Início (o papel do site lê; nenhum telefone sai)
SELECT cardinality(site_painel_internos()) AS internos;
SET ROLE nay_site_leitura;
SELECT k, v::text FROM jsonb_each(site_painel_metricas(current_date - 13, current_date, 'dia') -> 'serie') x(k, v) ORDER BY k;
SELECT site_painel_metricas(current_date - 29, current_date, 'dia') -> 'totais' AS totais_30_dias;
SELECT site_painel_metricas(current_date - 29, current_date, 'dia') -> 'top_imoveis' AS top;
SELECT site_painel_metricas(current_date - 40, current_date, 'semana') -> 'coortes_disparo' AS coortes;
SELECT site_painel_metricas(current_date - 40, current_date, 'semana') -> 'funil_olx' AS funil;
SELECT site_painel_metricas(current_date - 40, current_date, 'mes') -> 'fechamentos' AS fech;
SELECT site_painel_metricas(current_date - 60, current_date, 'semana') -> 'periodos' AS semanas,
       site_painel_metricas(current_date - 60, current_date, 'mes') -> 'periodos' AS meses;
RESET ROLE;
EXPLAIN (ANALYZE, TIMING OFF, SUMMARY ON, COSTS OFF) SELECT site_painel_metricas(current_date - 89, current_date, 'dia');
