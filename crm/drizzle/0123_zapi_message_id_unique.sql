-- Dedupe das mensagens que entram pela Z-API.
--
-- A Z-API reenvia o webhook quando a nossa resposta demora ou falha, e o
-- processamento em src/lib/zapiInbound.ts só compara as 100 últimas atividades
-- DAQUELE lead. Esse índice é a rede de segurança global — mesma defesa que já
-- existe para evolution_message_id, whatsapp_message_id e instagram_message_id.
--
-- Único e parcial: linhas sem `zapi_message_id` (mensagem enviada pelo CRM por
-- outro canal, atividade de sistema) não entram no índice e não competem entre si.
CREATE UNIQUE INDEX IF NOT EXISTS "lead_activities_zapi_msgid_unique"
  ON "lead_activities" ((metadata->>'zapi_message_id'))
  WHERE metadata->>'zapi_message_id' IS NOT NULL;
