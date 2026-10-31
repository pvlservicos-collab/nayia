-- 554a (Pedro, 31/10/2026: "termina minha integração com o chat do chaves na mão e põe a mesma Nay da OLX para
-- responder lá com os mesmos objetivos"): o cliente da Nay do WhatsApp (8595) pode vir do Chaves na Mão.
-- Só o esquema, curto e com lock_timeout (ensaio-sem-ddl-no-banco-vivo); as funções estão na 554.
BEGIN;
SET LOCAL lock_timeout = '5s';
ALTER TABLE privado.olx_lead_whatsapp DROP CONSTRAINT olx_lead_whatsapp_origem_check;
ALTER TABLE privado.olx_lead_whatsapp ADD CONSTRAINT olx_lead_whatsapp_origem_check
  CHECK (origem = ANY (ARRAY['olx'::text, 'organico'::text, 'manual'::text, 'chavesnamao'::text]));
COMMENT ON COLUMN privado.olx_lead_whatsapp.origem IS
  'olx (deu o número no chat da OLX) · organico (escreveu direto) · manual (aberto pelo CRM) · chavesnamao (554: lead do portal Chaves na Mão)';
COMMIT;
