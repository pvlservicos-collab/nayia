-- 480 (Pedro, 23/10/2026): a busca do cliente sai do teste para os anunciantes da OLX e para a Nay dos corretores,
-- e a lista de grupos do 8595 ganha 3 grupos.
--   "esses testes que me enviaram no whatsapp já era para ter chamado os corretores e não eu"
--   "atualizei a lista de grupos ... demais manda venda e locação: MERCADO IMOBILIÁRIO 2026, Novos Negócios
--    Imobiliários - AM, Oportunidades Manaus 2026"
-- A regra dos 6 que já estavam não muda (Locação CREDENCIADOS só locação; Alto Padrão locação >= 7 mil e venda
-- >= 800 mil; os outros, tudo). busca_grupos e busca_fluxo seguem em 'teste' (não foram pedidos).
-- O que foi perguntado em teste não conta quando vira 'sim': os anunciantes dos testes recebem a pergunta de verdade.
BEGIN;

INSERT INTO privado.busca_grupo (grupo_id, nome, locacao, venda, locacao_min, venda_min) VALUES
  ('120363023894631899-group', 'MERCADO IMOBILIÁRIO 2026', true, true, NULL, NULL),
  ('559292480860-1593617766', 'Novos Negócios Imobiliários - AM', true, true, NULL, NULL),
  ('120363039682957370-group', '🏠🔥 Oportunidades Manaus 2026 💰✨', true, true, NULL, NULL)
ON CONFLICT (grupo_id) DO UPDATE SET locacao = true, venda = true, locacao_min = NULL, venda_min = NULL, ativo = true;

UPDATE privado.olx_config SET valor = 'sim' WHERE chave IN ('busca_olx', 'busca_corretor');

COMMIT;
