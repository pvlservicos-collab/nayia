SELECT coalesce(x->>'mobilia', '(sem)') AS mobilia, count(*) FROM jsonb_array_elements(site_imoveis_para_enviar()) x GROUP BY 1 ORDER BY 2 DESC;
SELECT jsonb_array_length(site_imoveis_para_enviar()) AS imoveis;
