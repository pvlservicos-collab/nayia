-- 355 -- O "até 20h" do Pedro é no horário dele (Brasília, 1 h na frente de Manaus): a janela fecha às 19:00 de Manaus
--
-- Pedro, 12/10/2026: "são 19:44 no meu horário" (o banco marcava 18:44) e "se ajuste a isso, eu tô falando de disparo
-- na API oficial". A 354 tinha aberto até 20:00 de Manaus (21:00 para ele).
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE captacao_config SET valor = '19:00' WHERE chave = 'janela_fim';

COMMIT;
