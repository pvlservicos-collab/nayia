-- teste da 387 (na ensaio: termina em ROLLBACK)
-- o Pedro está com a Nay do WhatsApp (lead 1): a mensagem dele vira 'Recebido olx'
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES ('5596991712835', 'recebida', 'texto', 'teste 387', 'Recebido')
RETURNING status AS do_pedro;
-- outro número da lista do python (sem Nay do WhatsApp): continua 'Recebido py' se estiver na lista; um qualquer, 'Recebido'
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES ('5592900000001', 'recebida', 'texto', 'teste 387', 'Recebido')
RETURNING status AS de_um_qualquer;
-- a equipe assumiu o lead do Pedro: volta a ser da Nay dos proprietários
UPDATE privado.olx_lead_whatsapp SET humano_em = now() WHERE id = 1;
INSERT INTO captacao_mensagens (telefone, direcao, origem, texto, status) VALUES ('5596991712835', 'recebida', 'texto', 'teste 387', 'Recebido')
RETURNING status AS do_pedro_com_a_equipe;
