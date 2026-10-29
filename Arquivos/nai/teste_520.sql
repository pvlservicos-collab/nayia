-- 520: ensaio (tudo desfeito)
SET ROLE nay_disparo;
SELECT etapa, passo, finalidade, visita_confirmada, count(*) FROM crm_olx_clientes_etapas() GROUP BY 1, 2, 3, 4 ORDER BY 2, 1, 3;
SELECT count(*) AS linhas FROM crm_olx_clientes_etapas();
RESET ROLE;
