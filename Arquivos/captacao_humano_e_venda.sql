-- =====================================================================
-- Captacao -- dois pedidos do Tel em 11/09/2026:
--
-- 1. QUER VENDER. "Para locacao nao, quero vender" (Sr. Luis, 10/09) foi
--    gravado como situacao = vendido -- que e quem JA vendeu. Quem quer
--    vender e outra coisa, e ela tem que perguntar o VALOR que ele quer.
--    Colunas novas: quer_vender, valor_venda_pedido.
--
-- 2. O TEL ASSUMIU. Se o Tel mandou mensagem naquele chat (pelo celular do
--    numero da campanha), a Nay para de responder ali para sempre, e o
--    disparo e o lembrete tambem nao chamam mais. Coluna nova:
--    humano_assumiu_em. E a "lista negra" da IA: o que chegar desse chat
--    fica gravado, mas ela nao responde.
--
-- So ACRESCENTA colunas (nada e apagado). A correcao do Sr. Luis e a
-- unica escrita em dado existente, e esta explicada abaixo.
-- =====================================================================

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS quer_vender boolean NOT NULL DEFAULT false;
ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS valor_venda_pedido text;
ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS humano_assumiu_em timestamptz;
ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS humano_motivo text;

COMMENT ON COLUMN captacao_leads.quer_vender IS 'O proprietario QUER vender (nao confundir com situacao=vendido, que e quem ja vendeu).';
COMMENT ON COLUMN captacao_leads.valor_venda_pedido IS 'Quanto ele quer pedir na venda, nas palavras dele.';
COMMENT ON COLUMN captacao_leads.humano_assumiu_em IS 'O Tel assumiu este chat: a Nay nao responde mais aqui e o disparo/lembrete nao chamam.';

-- Sr. Luis (lead 487): disse "Para locacao nao, quero vender" e "Preciso
-- receber liquido nessa casa 650 mil". Estava como vendido (erro da Nay).
UPDATE captacao_leads
   SET situacao = NULL, quer_vender = true,
       valor_venda_pedido = coalesce(valor_venda_pedido, '650 mil líquido (ele disse em 11/09)'),
       motivo_fim = 'corrigido em 11/09: estava vendido, mas ele QUER vender',
       atualizado_em = now()
 WHERE id = 487 AND situacao = 'vendido' AND NOT quer_vender;
