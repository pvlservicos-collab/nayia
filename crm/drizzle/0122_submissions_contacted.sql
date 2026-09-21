-- Marca que alguém já abriu a conversa com este lead pelo botão "Enviar
-- mensagem" da tela de Leads.
--
-- Fica em lead_source_submissions e não em leads de propósito: a marca é sobre
-- a LINHA da lista (aquele lead daquela fonte já foi trabalhado), não sobre o
-- lead em si — que pode receber mensagem por muitos outros caminhos (chat,
-- funil, resposta a uma dúvida) sem que isso signifique "já contatei da lista".
ALTER TABLE "lead_source_submissions"
  ADD COLUMN IF NOT EXISTS "contacted_at" timestamptz,
  ADD COLUMN IF NOT EXISTS "contacted_by_member_id" uuid;
