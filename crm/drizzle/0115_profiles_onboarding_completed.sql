-- Onboarding guiado no primeiro login (tour em /welcome: conectar WhatsApp, overview
-- de funções, CTA final). Contas que já existem antes desta feature não devem ver o
-- tour retroativamente — por isso o backfill abaixo marca true pra todo mundo que já
-- está na base; só contas criadas depois (via /ativar-conta ou "Novo Membro" em
-- Configurações > Membros) nascem com false e caem em /welcome no primeiro login.
ALTER TABLE "profiles" ADD COLUMN "onboarding_completed" boolean DEFAULT false;
UPDATE "profiles" SET "onboarding_completed" = true;
