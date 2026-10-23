-- 481 -- A busca do cliente: os pedidos nos grupos de verdade e o valor mínimo que a casa atende
--
-- Pedro, 23/10/2026 (tela Buscar imóvel OLX, a busca 43: casa à venda até R$ 150 mil): "não apareceu nenhuma mensagem
-- para grupos ainda" (busca_grupos estava em 'teste': os 18 pedidos foram só ao número de teste) e "não atendemos leads de
-- imóveis abaixo de 200 mil ou abaixo de 2k de aluguel, não precisa fazer a busca desses".
-- - busca_grupos = 'sim': o pedido vai ao grupo pelo 8595, uma busca por mensagem, 15 min entre mensagens no mesmo grupo.
-- - busca_venda_min / busca_aluguel_min: abaixo disso a busca não é ativada e a aberta é encerrada (nay-olx olx/buscas.py).
-- - busca_lote_min deixa de ser lida: grupos e OLX saem juntos, logo depois da nossa base.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE privado.olx_config SET valor = 'sim', atualizado_em = now(), atualizado_por = '481'
 WHERE chave = 'busca_grupos';

INSERT INTO privado.olx_config (chave, valor, descricao, atualizado_por) VALUES
  ('busca_venda_min', '200000', 'Busca do cliente: venda com valor abaixo disto (R$) não é buscada fora (Pedro, 23/10).', '481'),
  ('busca_aluguel_min', '2000', 'Busca do cliente: aluguel com valor abaixo disto (R$) não é buscado fora (Pedro, 23/10).', '481')
ON CONFLICT (chave) DO NOTHING;

UPDATE privado.olx_config SET descricao = 'Não é mais lida (481): grupos e OLX saem juntos, logo depois da nossa base.',
       atualizado_em = now(), atualizado_por = '481'
 WHERE chave = 'busca_lote_min';

COMMIT;
