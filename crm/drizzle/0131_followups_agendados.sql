-- 0131 -- FOLLOW-UP AGENDADO (Pedro, 30/09/2026): "no card do contato, onde tem instrução
-- para a Nay, um campo agendar follow-up: eu coloco a mensagem, quando quero que envie
-- (amanhã, uma semana ou data específica) e a hora, clico em salvar e o sistema salva".
-- Quem envia é /api/cron/followups (a cada minuto), pela linha da própria conversa.
BEGIN;
SET LOCAL lock_timeout = '5s';
-- o CRM entra no crmdb como `crm` (não superusuário): a tabela tem de ser dele
SET LOCAL ROLE crm;
CREATE TABLE IF NOT EXISTS followups_agendados (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  lead_id         uuid NOT NULL,
  mensagem        text NOT NULL,
  enviar_em       timestamptz NOT NULL,
  estado          text NOT NULL DEFAULT 'agendado' CHECK (estado IN ('agendado', 'enviando', 'enviado', 'falhou', 'cancelado')),
  criado_por      uuid,
  criado_por_nome text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  enviado_em      timestamptz,
  erro            text
);
CREATE INDEX IF NOT EXISTS followups_agendados_vencidos ON followups_agendados (enviar_em) WHERE estado = 'agendado';
CREATE INDEX IF NOT EXISTS followups_agendados_lead ON followups_agendados (lead_id, enviar_em DESC);
COMMIT;
