-- 254 (01/10/2026): A CONVERSA DA ALESSANDRA BARROS VAI PARA A ETAPA DO TEL.
-- Pedro: "consegue puxar a conversa de antes com essa vendedora? lá do Nay
-- parceria. Tem na Z-API mas não aparece lá no CRM. Puxa e põe lá na etapa do
-- Tel e avisa ele lá no CRM".
--
-- 92 98127-1044, Alessandra Barros, contato 5391 da Nay. O que havia:
--   * no naydb, 6 mensagens dela de 15/09 (19:47 às 20:05), todas recebidas --
--     a última, "Vcs podem vender normal sem permuta";
--   * no CRM, NADA: nem o lead existia;
--   * o Tel assumiu a conversa naquele dia 20:05 (humano_assumiu_em).
--
-- A Z-API NÃO DEVOLVE O HISTÓRICO: `chat-messages/<fone>` responde "Does not
-- work in multi device version". Então o que foi trazido para o CRM é o que o
-- NOSSO sistema gravou -- as 6 dela --, pela conferência de sempre
-- (/api/cron/espelho-nay?desde=...&ate=...). O que o Tel respondeu pelo
-- celular não está em nenhum registro nosso.
--
-- Aqui só a parte da Nay: a conversa passa a ser do Tel (ela cala até alguém
-- devolver). O lado do CRM (etapa no card, observação e o aviso ao Tel) é feito
-- no crmdb, junto.
BEGIN;
SET LOCAL lock_timeout = '3s';

SELECT c.chave, (crm_etapa_manual(c.telefone, 'tel', 'Pedro (pedido no chat, 01/10)')).*
  FROM nai_contato c
 WHERE right(c.chave, 8) = '81271044' AND c.telefone IS NOT NULL;
COMMIT;
