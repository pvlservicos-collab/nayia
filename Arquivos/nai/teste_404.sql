-- 404: listar, marcar e contar (o papel do site)
SELECT max(id) AS vid FROM nai_visita WHERE quando < now() AND excluida_em IS NULL \gset
SET ROLE nay_site_escrita;
SELECT jsonb_array_length(site_painel_visitas(current_date - 29, current_date)) AS visitas_30_dias;
SELECT site_painel_visitas(current_date - 3, current_date) -> 0 AS uma;
SELECT site_painel_visita_marcar('parceria', :vid, 'fechou', 'ensaio');
SELECT site_painel_visita_marcar('olx', 2, 'realizada', 'ensaio');
SELECT site_painel_visita_marcar('olx', 2, 'xpto', 'ensaio') AS recusa;
SELECT k, v FROM jsonb_each(site_painel_metricas(current_date - 29, current_date, 'dia') -> 'totais') x(k, v)
 WHERE k LIKE 'visitas%' ORDER BY k;
SELECT site_painel_visita_marcar('olx', 2, '', 'ensaio') AS limpou;
RESET ROLE;
