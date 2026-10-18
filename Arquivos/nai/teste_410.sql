SET ROLE nay_site_escrita;
SELECT site_whats_modelo_nota_salvar('{"nome":"teste_410","etiquetas":["Captação"," dono ","Captação"],"observacao":"só teste"}'::jsonb, 'teste') AS criou;
SELECT site_whats_modelo_nota_salvar('{"nome":"teste_410","etiquetas":["dono","Corretor"]}'::jsonb, 'teste') AS trocou_etiquetas_manteve_obs;
SELECT site_whats_modelos_notas()->'notas'->'teste_410|pt_BR' AS nota, site_whats_modelos_notas()->'etiquetas' AS todas;
SELECT site_whats_modelo_nota_salvar('{"nome":"","etiquetas":[]}'::jsonb, 'teste') AS sem_nome;
RESET ROLE;
DELETE FROM whats_modelo_nota WHERE nome = 'teste_410';
