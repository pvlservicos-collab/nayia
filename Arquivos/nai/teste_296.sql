SELECT count(*) AS pessoas, count(*) FILTER (WHERE imoveis > 0) AS com_imovel, count(*) FILTER (WHERE imoveis = 0) AS sem_imovel,
       count(*) FILTER (WHERE nome IS NULL) AS sem_nome, sum(imoveis) AS imoveis_somados FROM vw_proprietarios_site;
SELECT etapa, count(*) FROM vw_proprietarios_site GROUP BY 1 ORDER BY 2 DESC LIMIT 6;
-- nenhum imóvel em dois donos
SELECT count(*) AS imoveis_em_mais_de_um_dono FROM (
  SELECT c FROM vw_proprietarios_site v, regexp_split_to_table(v.codigos, ', ') c GROUP BY c HAVING count(*) > 1) x;
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF, SUMMARY ON) SELECT p.*, count(*) OVER () FROM vw_proprietarios_site p ORDER BY p.nome LIMIT 30;
