-- Permite gerar um convite (/ativar-conta) pra um papel específico da org (ex:
-- "Founder"), em vez de sempre criar como "Admin".
ALTER TABLE "setup_tokens" ADD COLUMN "role_name" text;
