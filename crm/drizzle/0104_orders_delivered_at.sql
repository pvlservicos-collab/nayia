-- Captura automática de quando um pedido foi marcado como entregue
ALTER TABLE "orders" ADD COLUMN "delivered_at" timestamptz;
