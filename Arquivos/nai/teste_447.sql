-- teste da 447: roda dentro da transação do ensaio (antes do ROLLBACK)
\echo '--- quantos entraram (esperado ~163), e o perfil'
SELECT count(*) AS entraram, count(*) FILTER (WHERE tratamento IS NULL) AS sem_tratamento,
       count(*) FILTER (WHERE imovel_desc IS NULL) AS sem_imovel_desc, count(DISTINCT telefone_chave) AS chaves
  FROM captacao_leads WHERE modelo_abertura = 'outro_imovel_04';
\echo '--- nenhum deles falou conosco em 60 dias, nem é corretor (esperado 0 e 0)'
SELECT count(*) FILTER (WHERE nay_falou_conosco(telefone_chave, 60)) AS falou60,
       count(*) FILTER (WHERE nay_e_corretor_chave(telefone_chave)) AS corretor
  FROM captacao_leads WHERE modelo_abertura = 'outro_imovel_04';
\echo '--- modelo ainda não aprovado: nenhum na fila (esperado 0)'
SELECT count(*) AS na_fila_sem_aprovar FROM captacao_py_fila_do_disparo() f(id)
  JOIN captacao_leads l ON l.id = f.id WHERE l.modelo_abertura IS NOT NULL;
\echo '--- a fila antiga continua igual'
SELECT count(*) AS fila_antiga FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id WHERE l.modelo_abertura IS NULL;
\echo '--- com o modelo aprovado, entram na fila (esperado = entraram)'
UPDATE captacao_config SET valor = 'situacao_imovel_cadastrado_1, outro_imovel_04' WHERE chave = 'python_modelos_aprovados';
SELECT count(*) AS na_fila_aprovado FROM captacao_py_fila_do_disparo() f(id)
  JOIN captacao_leads l ON l.id = f.id WHERE l.modelo_abertura = 'outro_imovel_04';
\echo '--- sem a pergunta dos honorários na campanha (esperado 0 com frase), e a de um lead antigo continua'
SELECT count(*) FILTER (WHERE captacao_honorarios_frase(telefone) IS NOT NULL) AS com_frase
  FROM captacao_leads WHERE modelo_abertura = 'outro_imovel_04';
SELECT count(*) FILTER (WHERE captacao_honorarios_frase(telefone) IS NOT NULL) AS antigos_com_frase
  FROM captacao_leads WHERE quem_importou LIKE 'Pedro (lista 6:%';
\echo '--- três exemplos'
SELECT id, tratamento, nome, codigo, tipo_imovel, imovel_desc, etapa, status FROM captacao_leads
 WHERE modelo_abertura = 'outro_imovel_04' ORDER BY id LIMIT 3;
