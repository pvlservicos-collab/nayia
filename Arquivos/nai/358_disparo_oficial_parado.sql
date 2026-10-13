-- 358 -- Disparo pela API oficial PARADO
--
-- Pedro, 13/10/2026: "pode parar o disparo, e vamos continuar amanhã quando eu avisar aqui manualmente".
-- Só o disparo: a Nay de captação continua respondendo quem escreve. A fila fica como está (quem é 'novo' continua
-- 'novo'). Para religar: `python_disparo = sim`, SÓ com o aviso dele.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE captacao_config SET valor = 'nao' WHERE chave = 'python_disparo';

COMMIT;
