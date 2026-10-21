SELECT campanha, count(*) FROM captacao_leads WHERE modelo_abertura='outro_imovel_04' GROUP BY 1;
SELECT count(*) AS na_fila FROM captacao_py_fila_do_disparo();
