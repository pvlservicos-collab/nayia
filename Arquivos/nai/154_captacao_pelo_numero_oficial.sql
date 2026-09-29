-- =====================================================================
-- 154 — A NAY DE CAPTAÇÃO CONVERSA PELO NÚMERO OFICIAL (28/09/2026)
--
-- Pedro: "a nay de captação vai agora conversar pelo número oficial".
--
-- A captação sempre conversou pela Z-API (92 8595-6408). O primeiro contato
-- agora é template da Meta (modelou4 etc.) pelo 92 8456-0874, e quem responde
-- o template responde LÁ. O CRM recebe da Meta e repassa ao fluxo da captação
-- (webhook captacao-oficial-2026), e a resposta da Nay volta pelo CRM
-- (/api/webhooks/captacao-oficial).
--
-- `captacao_leads.canal` guarda por qual número o dono escreveu por último --
-- é por esse que a Nay responde. NULL/'zapi' = Z-API, como sempre foi.
-- Quem grava é o nó "Gravar na fila"; quem lê é o "Ainda é da IA?".
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS canal text;
COMMENT ON COLUMN captacao_leads.canal IS
  'Por qual número o dono escreveu por último: oficial (8456-0874, via CRM) ou zapi (8595-6408). A Nay responde por ele. (154, 28/09)';

COMMIT;
