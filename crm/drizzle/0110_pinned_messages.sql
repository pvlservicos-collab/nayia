-- Fixar mensagem dentro da conversa (não existia antes). Tabela separada do
-- metadata da activity para não concorrer com outros escritores (reply, reações,
-- status de envio) e para listar/paginar fixadas sem varrer a conversa inteira.
-- Sem nenhum limite de quantidade — é o pedido central da feature.

CREATE TABLE "pinned_messages" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "lead_id" uuid NOT NULL REFERENCES "leads"("id") ON DELETE CASCADE,
  "activity_id" uuid NOT NULL REFERENCES "lead_activities"("id") ON DELETE CASCADE,
  "pinned_by_member_id" uuid,
  "pinned_at" timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX "pinned_messages_lead_activity_unique" ON "pinned_messages" ("lead_id", "activity_id");
CREATE INDEX "pinned_messages_lead_pinned_at_idx" ON "pinned_messages" ("lead_id", "pinned_at");
