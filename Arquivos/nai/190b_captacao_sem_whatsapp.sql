-- 190b -- o status 'sem_whatsapp' existe (29/09/2026).
--
-- O nó "Sem WhatsApp" do fluxo da captação (28/09) marca o dono cujo número
-- não tem WhatsApp, para ele sair da fila sem gastar tentativa. Mas a regra
-- `captacao_lead_status_ok` não conhecia esse valor: o UPDATE quebrava, a
-- execução terminava em erro e o lead ficava 'reservado'. Com um lead
-- reservado, o "Pegar lead novo" não reserva ninguém ("um de cada vez"), então
-- a FILA INTEIRA parava até o destravador de 30 minutos soltar -- e voltava a
-- tentar o mesmo número. Em 29/09 foi assim das 17:28 até o fim da janela.

BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE captacao_leads DROP CONSTRAINT captacao_lead_status_ok;
ALTER TABLE captacao_leads ADD CONSTRAINT captacao_lead_status_ok
  CHECK (status = ANY (ARRAY['novo', 'reservado', 'enviado', 'erro', 'respondendo', 'concluido', 'sem_whatsapp']));
COMMIT;
