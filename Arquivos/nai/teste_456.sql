-- teste da 456
SELECT campanha, count(*) AS entraram, count(*) FILTER (WHERE tratamento IS NULL) AS sem_tratamento,
       count(*) FILTER (WHERE imovel_desc IS NULL) AS sem_imovel_desc
  FROM captacao_leads WHERE modelo_abertura = 'outro_imovel_04' GROUP BY 1 ORDER BY 1;
SELECT count(*) FILTER (WHERE nay_falou_conosco(telefone_chave, 60)) AS falou60, count(*) FILTER (WHERE nay_e_corretor_chave(telefone_chave)) AS corretor,
       count(DISTINCT telefone_chave) AS chaves, count(*) AS linhas
  FROM captacao_leads WHERE modelo_abertura = 'outro_imovel_04';
SELECT count(*) AS na_fila_sem_aprovar FROM captacao_py_fila_do_disparo();
SELECT jsonb_path_query_array(crm_captacao_disparo_oficial(), '$.listas[*] ? (@.esperando > 0)') AS listas_esperando;
