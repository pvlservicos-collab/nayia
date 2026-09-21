-- "Arquivar conversa" (igual WhatsApp) — some da aba "Todos", fica só em "Arquivados"
-- até chegar mensagem nova do cliente (aí desarquiva sozinho) ou alguém desarquivar.
ALTER TABLE "leads" ADD COLUMN "is_archived" boolean DEFAULT false;
