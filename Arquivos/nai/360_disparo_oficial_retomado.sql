-- 360 (13/10/2026): o Pedro avisou para retomar o disparo oficial parado na 358 ("sim retome o disparo").
-- Sai o que falta das listas 6 e 8 (107 na fila), no ritmo de antes (25 a 35 s) e dentro da janela (08:00-19:00
-- de Manaus). As garantias da 351/352 continuam valendo: quem falou conosco em 60 dias e corretor ficam de fora.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE captacao_config SET valor = 'sim' WHERE chave = 'python_disparo';

COMMIT;
