-- Soft delete de pedidos: excluir na Logística remove o pedido de listagens e totais do financeiro
ALTER TABLE "orders" ADD COLUMN "deleted_at" timestamptz;
