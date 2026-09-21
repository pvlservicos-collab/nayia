-- Log de leads recebidos por fonte externa (Agenda Ascensão, Site Evento, ...).
--
-- Uma linha por lead recebido, por fonte. Os campos de contato ficam em colunas
-- próprias porque são os mesmos em toda fonte (é o que a tela lista e o que liga
-- no lead do CRM); tudo que é específico da fonte fica em `payload`, o corpo
-- normalizado como chegou. Assim adicionar uma fonte nova com outros campos é
-- só registrar ela em src/lib/leadSources.ts — não precisa de migration.
CREATE TABLE "lead_source_submissions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "source" text NOT NULL,
  -- Chave de deduplicação vinda da fonte: o `id` numérico na Agenda, o telefone
  -- no Site. Permite reenviar o mesmo lead (ex: quiz que era "w1" e virou
  -- "done") atualizando a linha em vez de duplicar.
  "external_id" text,
  "name" text,
  "email" text,
  "phone" text,
  "instagram" text,
  "payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- Lead do CRM criado/encontrado a partir deste envio. Nullable porque o log
  -- existe mesmo se a criação do lead falhar — o dado recebido nunca se perde.
  "lead_id" uuid,
  "received_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now()
);

-- O upsert do endpoint de ingestão depende deste índice (ON CONFLICT).
CREATE UNIQUE INDEX "lead_source_submissions_dedupe_unique"
  ON "lead_source_submissions" ("organization_id", "source", "external_id")
  WHERE "external_id" IS NOT NULL;

-- Consulta da tela: uma fonte por vez, mais recentes primeiro.
CREATE INDEX "lead_source_submissions_org_source_idx"
  ON "lead_source_submissions" ("organization_id", "source", "received_at" DESC);
