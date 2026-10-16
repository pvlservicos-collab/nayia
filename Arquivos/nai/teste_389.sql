INSERT INTO privado.olx_visita (lead, codigo, quando) VALUES (2, 5724, now() + interval '1 day') RETURNING id, estado;
INSERT INTO privado.olx_visita_consulta (visita, papel, nome, telefone) SELECT max(id), 'corretor', 'Teste', '92911112222' FROM privado.olx_visita RETURNING estado;
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES ('5592911112222', 'recebida', 'texto', 'sim posso', 'Recebido') RETURNING status AS do_corretor;
SELECT chave, valor FROM privado.olx_config WHERE chave LIKE 'visita%';
