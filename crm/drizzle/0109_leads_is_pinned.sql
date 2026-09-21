-- "Fixar conversa" já existia na UI (LeadList.tsx) mas nunca persistia: o campo
-- is_pinned só existia no tipo TS do front, nunca foi uma coluna real. Adicionando
-- agora para o toggle passar a sincronizar entre sessões/atendentes de verdade.

ALTER TABLE "leads" ADD COLUMN "is_pinned" boolean DEFAULT false;
