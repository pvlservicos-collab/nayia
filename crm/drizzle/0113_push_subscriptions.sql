-- Inscrições de push (Web Push/VAPID), uma linha por navegador/aparelho.
CREATE TABLE "push_subscriptions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "member_id" uuid NOT NULL,
  "endpoint" text NOT NULL,
  "p256dh" text NOT NULL,
  "auth" text NOT NULL,
  "user_agent" text,
  "created_at" timestamptz DEFAULT now(),
  "last_seen_at" timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX "push_subscriptions_endpoint_unique" ON "push_subscriptions" ("endpoint");
CREATE INDEX "push_subscriptions_member_idx" ON "push_subscriptions" ("member_id");
CREATE INDEX "push_subscriptions_org_idx" ON "push_subscriptions" ("organization_id");
