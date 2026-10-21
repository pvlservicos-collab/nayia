SELECT campanha, min(id), max(id), count(*) FROM captacao_leads WHERE modelo_abertura='outro_imovel_04' GROUP BY 1 ORDER BY 2;
SELECT chave, valor FROM captacao_config WHERE chave LIKE 'python_disparo_seg%';
