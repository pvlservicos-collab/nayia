SELECT codigo, status, valor_venda, andar, vagas_cobertas, caracteristicas FROM imoveis WHERE codigo IN (5707,5001,2944,9027,2539) ORDER BY 1;
SELECT cf.taxa_inclui FROM imoveis i JOIN condominio_ficha cf ON cf.condominio_id = i.condo_id WHERE i.codigo = 9021;
SELECT count(*) FROM privado.respostas_do_tel_antes_465;
