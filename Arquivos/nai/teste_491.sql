SELECT foi_ate, count(*), min(chegou_em)::date, max(chegou_em)::date FROM crm_leads_pipeline('2026-10-01', '2026-10-31') GROUP BY 1 ORDER BY 2 DESC;
SELECT nome, origem, chegou_em, etapa, foi_ate, imoveis, humano, visita_quando, procura FROM crm_leads_pipeline('2026-10-01', '2026-10-31') LIMIT 8;
SET ROLE nay_disparo;
SELECT count(*) AS como_o_crm FROM crm_leads_pipeline(current_date - 30, current_date);
RESET ROLE;
