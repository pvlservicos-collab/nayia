-- Status de assinatura controlado manualmente pelo painel /admin (sem gateway de
-- pagamento integrado ainda). Todo mundo começa 'active'.
ALTER TABLE "organizations" ADD COLUMN "subscription_status" text NOT NULL DEFAULT 'active';
