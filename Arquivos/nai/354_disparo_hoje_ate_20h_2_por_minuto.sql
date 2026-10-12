-- 354 -- Disparo da captação hoje (12/10) até as 20:00, 2 por minuto
--
-- Pedro, 12/10/2026 18:25: "começa o disparo nas listas [8 e 9] do situacao_imovel_cadastrado_1, 2 por minuto, até umas
-- 20 hrs". A lista 9 é toda a captação: os 280 "para falar" são os 151 que a 353 pôs na fila (listas 6 e 8) mais 4 que
-- não saem (3 sem WhatsApp, 1 com o Tel). A janela dos dias úteis fechava às 18:00 (a 353 entrou 18:15): abre até 20:00.
-- Ritmo: o serviço nay-captacao sorteia o intervalo entre python_disparo_seg_min e _seg_max a cada volta (lê do banco).
-- 25-35 s = 2 por minuto. De 18:30 às 20:00 saem os ~151; o que sobrar sai amanhã a partir das 08:00.
--
-- !! A janela fica 08:00-20:00 nos dias úteis até alguém voltar a 18:00 (o Tel não mandou voltar).
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE captacao_config SET valor = '20:00' WHERE chave = 'janela_fim';
UPDATE captacao_config SET valor = '25'    WHERE chave = 'python_disparo_seg_min';
UPDATE captacao_config SET valor = '35'    WHERE chave = 'python_disparo_seg_max';

COMMIT;
