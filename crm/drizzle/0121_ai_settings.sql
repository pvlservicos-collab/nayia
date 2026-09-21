-- Configuração da IA, uma linha por organização.
--
-- Nasce DESLIGADA (`enabled = false`) de propósito: o prompt pode ser escrito e
-- revisado com calma antes de qualquer coisa responder cliente no lugar de uma
-- pessoa. Nada no app consome esta tabela ainda — ela guarda a configuração
-- para quando a IA for conectada.
CREATE TABLE "ai_settings" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "enabled" boolean NOT NULL DEFAULT false,
  "model" text NOT NULL DEFAULT 'claude-opus-5',
  "system_prompt" text NOT NULL DEFAULT '',
  -- Regras que a pessoa quer que a IA nunca quebre, separadas do prompt
  -- principal pra ficarem fáceis de revisar sem ler o texto todo.
  "guardrails" text NOT NULL DEFAULT '',
  "updated_by_member_id" uuid,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now()
);

-- Uma configuração por organização.
CREATE UNIQUE INDEX "ai_settings_org_unique" ON "ai_settings" ("organization_id");
