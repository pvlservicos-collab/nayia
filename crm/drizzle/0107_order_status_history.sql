-- Histórico de mudanças de status do pedido (pagamento e entrega), com data/hora
-- e responsável — base para o rastreamento de pedidos na Logística.

CREATE TABLE "order_status_history" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "order_id" uuid NOT NULL REFERENCES "orders"("id") ON DELETE CASCADE,
  "field" text NOT NULL,
  "from_status" text,
  "to_status" text NOT NULL,
  "changed_by_member_id" uuid,
  "changed_at" timestamptz DEFAULT now()
);

CREATE INDEX "order_status_history_order_idx" ON "order_status_history" ("order_id", "changed_at");
