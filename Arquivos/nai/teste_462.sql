-- teste da 462 (dentro do ensaio): a dúvida nova da Parceria não entra na fila do PV do Tel; com a chave em 'nao', entra
SELECT count(*) AS na_fila_antes FROM pergunta_fila;
INSERT INTO core_pendencia (chave, codigo, pergunta, faltou) VALUES ('5592999990001', 2207, 'tem piscina? (teste 462)', '{piscina}');
SELECT count(*) AS na_fila_depois_com_sim FROM pergunta_fila;
UPDATE nai_config SET valor = 'nao' WHERE chave = 'duvida_vai_ao_agente';
INSERT INTO core_pendencia (chave, codigo, pergunta, faltou) VALUES ('5592999990002', 2207, 'tem elevador? (teste 462)', '{elevador}');
SELECT count(*) AS na_fila_depois_com_nao FROM pergunta_fila;
SELECT * FROM nai_proprietario_do_imovel(2207);
