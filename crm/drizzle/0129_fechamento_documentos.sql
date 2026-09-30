-- 0129 -- OS DOCUMENTOS DO FECHAMENTO (Pedro, 30/09/2026): "o que a Nay não
-- identificou (foto, imagem, documento) abre uma lista suspensa para ela dizer qual
-- documento é", separado entre documentos do CORRETOR e do CLIENTE.
-- O automático (nome do arquivo, legenda, mensagem ao lado) é calculado na hora e
-- não mora aqui; aqui fica só a ESCOLHA DA RAYSSA, uma por mensagem de mídia.
-- Desfazer a escolha é apagar a linha (volta a valer o automático).
BEGIN;
SET LOCAL lock_timeout = '5s';
-- o CRM entra no crmdb como `crm` (não superusuário): a tabela tem de ser dele,
-- senão a aplicação não lê (foi o que aconteceu com a 0128, criada pelo `nay`)
SET LOCAL ROLE crm;
CREATE TABLE IF NOT EXISTS fechamento_documentos (
  activity_id uuid PRIMARY KEY REFERENCES lead_activities(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL,
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  documento text NOT NULL,
  papel text CHECK (papel IN ('inquilino', 'comprador', 'vendedor', 'corretor')),
  definido_por uuid,
  definido_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS fechamento_documentos_do_lead ON fechamento_documentos (lead_id);
COMMIT;
