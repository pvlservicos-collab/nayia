-- Funil de Mensagens: tabelas para o editor visual de automações com ramificação

CREATE TYPE "funnel_trigger" AS ENUM ('novo_pago', 'novo_recuperacao');
CREATE TYPE "funnel_block_type" AS ENUM ('trigger', 'message', 'wait', 'condition', 'end');
CREATE TYPE "funnel_branch" AS ENUM ('default', 'yes', 'no');
CREATE TYPE "funnel_execution_status" AS ENUM ('running', 'waiting', 'waiting_condition', 'completed', 'stopped');

CREATE TABLE "message_funnels" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "organization_id" uuid NOT NULL REFERENCES "organizations"("id"),
  "name" text NOT NULL,
  "trigger" "funnel_trigger" NOT NULL,
  "is_active" boolean DEFAULT false,
  "created_at" timestamptz DEFAULT now(),
  "updated_at" timestamptz DEFAULT now(),
  "deleted_at" timestamptz
);

CREATE TABLE "funnel_blocks" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "funnel_id" uuid NOT NULL REFERENCES "message_funnels"("id") ON DELETE CASCADE,
  "type" "funnel_block_type" NOT NULL,
  "config" jsonb DEFAULT '{}',
  "position_x" numeric(10,2) DEFAULT 0,
  "position_y" numeric(10,2) DEFAULT 0,
  "created_at" timestamptz DEFAULT now()
);

CREATE TABLE "funnel_connections" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "funnel_id" uuid NOT NULL REFERENCES "message_funnels"("id") ON DELETE CASCADE,
  "source_block_id" uuid NOT NULL REFERENCES "funnel_blocks"("id") ON DELETE CASCADE,
  "target_block_id" uuid NOT NULL REFERENCES "funnel_blocks"("id") ON DELETE CASCADE,
  "branch" "funnel_branch" DEFAULT 'default'
);

CREATE TABLE "funnel_executions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "funnel_id" uuid NOT NULL REFERENCES "message_funnels"("id") ON DELETE CASCADE,
  "organization_id" uuid NOT NULL,
  "lead_id" uuid NOT NULL REFERENCES "leads"("id") ON DELETE CASCADE,
  "current_block_id" uuid,
  "status" "funnel_execution_status" DEFAULT 'running',
  "wait_until" timestamptz,
  "context" jsonb DEFAULT '{}',
  "started_at" timestamptz DEFAULT now(),
  "updated_at" timestamptz DEFAULT now()
);

CREATE TABLE "funnel_click_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "execution_id" uuid NOT NULL REFERENCES "funnel_executions"("id") ON DELETE CASCADE,
  "block_id" uuid NOT NULL,
  "token" text NOT NULL UNIQUE,
  "target_url" text NOT NULL,
  "clicked" boolean DEFAULT false,
  "clicked_at" timestamptz,
  "created_at" timestamptz DEFAULT now()
);

CREATE TABLE "funnel_response_events" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  "execution_id" uuid NOT NULL REFERENCES "funnel_executions"("id") ON DELETE CASCADE,
  "block_id" uuid NOT NULL,
  "branch" "funnel_branch" NOT NULL,
  "created_at" timestamptz DEFAULT now()
);

CREATE INDEX "funnel_blocks_funnel_id_idx" ON "funnel_blocks" ("funnel_id");
CREATE INDEX "funnel_connections_funnel_id_idx" ON "funnel_connections" ("funnel_id");
CREATE INDEX "funnel_executions_status_idx" ON "funnel_executions" ("status");
CREATE INDEX "funnel_executions_funnel_id_idx" ON "funnel_executions" ("funnel_id");
