-- dentro do ensaio: com o limite em 1 e um disparo de mentira hoje, o portão fecha; domingo fecha
UPDATE captacao_config SET valor = '1' WHERE chave = 'python_limite_dia';
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES ('5500000000000', 'enviada', 'disparo', 'teste 485', 'Enviado');
SELECT captacao_py_disparo_motivo() AS com_limite_1_e_um_disparo;
UPDATE captacao_config SET valor = '1,2,3,4,5,6,7' WHERE chave = 'python_sem_disparo_dow';
UPDATE captacao_config SET valor = '250' WHERE chave = 'python_limite_dia';
SELECT captacao_py_disparo_motivo() AS todos_os_dias_sem_disparo;
