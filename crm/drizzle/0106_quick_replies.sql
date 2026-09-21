-- Respostas rápidas: biblioteca compartilhada (organização) + atalhos pessoais (por atendente)
CREATE TYPE "quick_reply_scope" AS ENUM ('shared', 'personal');

CREATE TABLE "quick_replies" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "scope" "quick_reply_scope" NOT NULL DEFAULT 'personal',
  "created_by_member_id" uuid,
  "shortcut" text NOT NULL,
  "category" text,
  "content" text NOT NULL DEFAULT '',
  "media_url" text,
  "media_type" text,
  "media_mimetype" text,
  "media_filename" text,
  "created_at" timestamptz DEFAULT now(),
  "updated_at" timestamptz DEFAULT now(),
  "deleted_at" timestamptz,
  CONSTRAINT "quick_replies_personal_requires_member" CHECK ("scope" = 'shared' OR "created_by_member_id" IS NOT NULL)
);

CREATE INDEX "quick_replies_org_scope_idx" ON "quick_replies" ("organization_id", "scope");
CREATE INDEX "quick_replies_org_member_idx" ON "quick_replies" ("organization_id", "created_by_member_id");

-- Atalho único (case-insensitive) por escopo: um só "/promo" na biblioteca compartilhada,
-- e um só "/promo" pessoal por atendente (dois atendentes podem ter o mesmo atalho pessoal).
CREATE UNIQUE INDEX "quick_replies_shared_shortcut_unique" ON "quick_replies" ("organization_id", lower("shortcut"))
  WHERE "scope" = 'shared' AND "deleted_at" IS NULL;

CREATE UNIQUE INDEX "quick_replies_personal_shortcut_unique" ON "quick_replies" ("organization_id", "created_by_member_id", lower("shortcut"))
  WHERE "scope" = 'personal' AND "deleted_at" IS NULL;
