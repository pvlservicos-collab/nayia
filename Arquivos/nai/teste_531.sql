-- 531: sem a chave, nada de parceiro (a Parceria igual); com a chave, o 9085 entra e parceiro antigo não
SELECT 'sem chave: parceiros' AS caso, count(*) FILTER (WHERE i.e_parceiro) AS n
  FROM nai_disparo_buscar('venda', 500000, 700000, NULL, NULL, NULL, NULL, 100) b JOIN imoveis i USING (codigo);
SELECT 'com chave: 9085 entra' AS caso, count(*) AS n
  FROM nai_disparo_buscar('venda', 600000, 650000, ARRAY['Parque 10'], NULL, NULL, NULL, 100, true) WHERE codigo = 9085;
SELECT 'com chave: antigos' AS caso, count(*) AS n
  FROM nai_disparo_buscar(NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, true) b
 WHERE imovel_parceiro_antigo(b.codigo);
SELECT 'com chave: parceiros novos (todos)' AS caso, count(*) AS n
  FROM nai_disparo_buscar(NULL, NULL, NULL, NULL, NULL, NULL, NULL, 100, true) b JOIN imoveis i USING (codigo)
 WHERE i.e_parceiro;
SELECT 'chamada de 8 argumentos (o CRM de hoje)' AS caso, count(*) AS n
  FROM nai_disparo_buscar('aluguel', 1000, 3000, NULL, NULL, NULL, NULL, 60);
