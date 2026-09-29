-- 0128 -- A PASTA DO CORRETOR (Pedro, 29/09/2026): "uma pasta embaixo dos
-- corretores para anexar os documentos dela para quando for preciso, ali eu vou
-- deixar os documentos dela salvos e fica no banco". O arquivo mora no disco do
-- CRM (/data/midia/documentos-corretores/<lead>/..., só com login); aqui fica o
-- registro. Apagar é marcar (apagado_em): documento não some por um clique.
BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE IF NOT EXISTS corretor_documentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  nome text NOT NULL,
  url text NOT NULL,
  tipo text,
  tamanho bigint,
  enviado_por uuid,
  criado_em timestamptz NOT NULL DEFAULT now(),
  apagado_em timestamptz
);
CREATE INDEX IF NOT EXISTS corretor_documentos_do_lead ON corretor_documentos (lead_id) WHERE apagado_em IS NULL;
COMMIT;
