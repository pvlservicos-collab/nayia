SELECT a.ficha_id, a.campos->>'condominio' AS dito, site_ficha_preparada(a.ficha_id)->'condominio'->>'nome' AS achou FROM captacao_ficha_campos a WHERE a.campos->>'condominio' IS NOT NULL ORDER BY 1;
