-- Dinheiro em espécie: o motoboy recebe fisicamente na entrega, então "pago" não
-- significa "já está com a empresa". cash_settled controla esse repasse à parte,
-- desacoplado de payment_status. Default true não afeta pedidos existentes nem
-- outros métodos de pagamento; só pedidos novos em dinheiro nascem com false.

ALTER TABLE "orders" ADD COLUMN "cash_settled" boolean NOT NULL DEFAULT true;
ALTER TABLE "orders" ADD COLUMN "cash_settled_at" timestamptz;
