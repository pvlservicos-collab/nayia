UPDATE mensagens SET status = 'Respondido' WHERE telefone = $1 AND status = 'Processando';
