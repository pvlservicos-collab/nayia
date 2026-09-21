-- ============================================================
-- Atlas Eye CRM — Migração para Neon (PostgreSQL)
-- Execute este arquivo no SQL Editor do Neon Console
-- console.neon.tech → seu projeto → SQL Editor
-- ============================================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ── Enums ────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE member_status AS ENUM ('active', 'invited', 'disabled');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE integration_status AS ENUM ('active', 'disabled');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE lead_activity_type AS ENUM ('note', 'call', 'whatsapp', 'email', 'system');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE custom_field_type AS ENUM ('text', 'number', 'date', 'bool', 'select', 'multi_select', 'json');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- ── Trigger atualiza updated_at ───────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ language 'plpgsql';

-- ── Tiers ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  max_users integer,
  can_use_custom_fields boolean DEFAULT false,
  permissions jsonb DEFAULT '{}'::jsonb
);

INSERT INTO tiers (name, max_users, can_use_custom_fields, permissions)
VALUES ('free', 3, false, '{}'), ('pro', 20, true, '{"custom_fields":true}'), ('enterprise', null, true, '{"custom_fields":true,"api":true}')
ON CONFLICT DO NOTHING;

-- ── Organizations ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  tier_id uuid REFERENCES tiers(id),
  timezone text DEFAULT 'UTC',
  logo_url text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_organizations_name ON organizations(name) WHERE deleted_at IS NULL;
DROP TRIGGER IF EXISTS update_organizations_modtime ON organizations;
CREATE TRIGGER update_organizations_modtime BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Users (substitui auth.users do Supabase) ─────────────────
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- ── Profiles ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  full_name text,
  avatar_url text,
  timezone text,
  is_superadmin boolean DEFAULT false
);

-- ── Sessions (NextAuth) ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON sessions(token);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);

-- ── Organization Roles ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organization_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  permissions jsonb DEFAULT '{}'::jsonb,
  version integer DEFAULT 1,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_org_roles_name ON organization_roles(organization_id, name);
DROP TRIGGER IF EXISTS update_org_roles_modtime ON organization_roles;
CREATE TRIGGER update_org_roles_modtime BEFORE UPDATE ON organization_roles FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Organization Members ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  user_id uuid NOT NULL REFERENCES profiles(id),
  role_id uuid NOT NULL REFERENCES organization_roles(id),
  status member_status DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_org_members_user ON organization_members(organization_id, user_id) WHERE deleted_at IS NULL;
DROP TRIGGER IF EXISTS update_org_members_modtime ON organization_members;
CREATE TRIGGER update_org_members_modtime BEFORE UPDATE ON organization_members FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Pipelines ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pipelines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  settings jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_pipelines_name ON pipelines(organization_id, name) WHERE deleted_at IS NULL;
DROP TRIGGER IF EXISTS update_pipelines_modtime ON pipelines;
CREATE TRIGGER update_pipelines_modtime BEFORE UPDATE ON pipelines FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Pipeline Stages ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pipeline_stages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  pipeline_id uuid NOT NULL REFERENCES pipelines(id),
  name text NOT NULL,
  color text,
  rank numeric(20, 6) NOT NULL,
  target_volume integer,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_pipeline_stages_rank ON pipeline_stages(pipeline_id, rank) WHERE deleted_at IS NULL;
DROP TRIGGER IF EXISTS update_pipeline_stages_modtime ON pipeline_stages;
CREATE TRIGGER update_pipeline_stages_modtime BEFORE UPDATE ON pipeline_stages FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Integrations ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS integrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  type text,
  config jsonb DEFAULT '{}'::jsonb,
  status integration_status DEFAULT 'active',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_integrations_org_name ON integrations(organization_id, name);
DROP TRIGGER IF EXISTS update_integrations_modtime ON integrations;
CREATE TRIGGER update_integrations_modtime BEFORE UPDATE ON integrations FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Integration Secrets (substitui vault do Supabase) ─────────
CREATE TABLE IF NOT EXISTS integration_secrets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  integration_id uuid NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL,
  secret jsonb NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_integration_secrets_integration ON integration_secrets(integration_id);

-- ── Leads ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  stage_id uuid REFERENCES pipeline_stages(id),
  integration_id uuid REFERENCES integrations(id),
  owner_member_id uuid REFERENCES organization_members(id),
  title text NOT NULL,
  external_id text,
  email text,
  phone text,
  avatar_url text,
  ai_interest_level text,
  ai_next_action_short text,
  custom_attributes jsonb DEFAULT '{}'::jsonb,
  last_message_content text,
  last_message_sender_type text,
  last_activity_at timestamptz,
  last_activity_type lead_activity_type,
  last_activity_by_member_id uuid,
  is_group boolean DEFAULT false,
  is_unread boolean DEFAULT false,
  value numeric(15, 2),
  goals jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE INDEX IF NOT EXISTS idx_leads_stage ON leads(organization_id, stage_id, created_at);
CREATE INDEX IF NOT EXISTS idx_leads_owner ON leads(organization_id, owner_member_id);
CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(organization_id, phone) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_leads_last_activity ON leads(organization_id, last_activity_at);
CREATE INDEX IF NOT EXISTS idx_leads_custom_attrs ON leads USING GIN (custom_attributes);
DROP TRIGGER IF EXISTS update_leads_modtime ON leads;
CREATE TRIGGER update_leads_modtime BEFORE UPDATE ON leads FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- ── Tags ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  color text DEFAULT '#6366f1',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_name ON tags(organization_id, name);

CREATE TABLE IF NOT EXISTS lead_tags (
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  tag_id uuid NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL,
  PRIMARY KEY (lead_id, tag_id)
);

-- ── Lead Activities ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lead_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  actor_member_id uuid REFERENCES organization_members(id),
  type lead_activity_type NOT NULL,
  content text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lead_activities_lead ON lead_activities(lead_id, created_at);
CREATE INDEX IF NOT EXISTS idx_lead_activities_org ON lead_activities(organization_id, created_at);

-- ── Custom Fields ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS custom_field_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  rank numeric(20, 6) NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS custom_field_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  category_id uuid REFERENCES custom_field_categories(id),
  name text NOT NULL,
  field_key text NOT NULL,
  field_type custom_field_type NOT NULL,
  options jsonb DEFAULT '[]'::jsonb,
  is_required boolean DEFAULT false,
  rank numeric(20, 6) NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_custom_fields_key ON custom_field_definitions(organization_id, field_key) WHERE deleted_at IS NULL;

-- ── Lead Stage History ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lead_stage_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  from_stage_id uuid REFERENCES pipeline_stages(id),
  to_stage_id uuid REFERENCES pipeline_stages(id),
  moved_by_member_id uuid REFERENCES organization_members(id),
  moved_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stage_history_lead ON lead_stage_history(lead_id, moved_at);

-- ── API Tokens ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS api_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  token_hash text NOT NULL UNIQUE,
  is_active boolean DEFAULT true,
  last_used_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- ── Notifications ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  recipient_member_id uuid NOT NULL REFERENCES organization_members(id),
  type text NOT NULL,
  title text NOT NULL,
  body text,
  metadata jsonb DEFAULT '{}'::jsonb,
  is_read boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications(recipient_member_id, is_read, created_at);

-- ── Setup Tokens ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS setup_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  token text NOT NULL UNIQUE,
  used_at timestamptz,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ── Webhook Logs ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS webhook_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payload jsonb,
  created_at timestamptz DEFAULT now()
);

-- ── Full-text Search (substitui RPC search_leads do Supabase) ─
CREATE OR REPLACE FUNCTION search_leads(
  p_org_id uuid,
  p_query text,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  lead_id uuid,
  match_type text,
  snippet text,
  matched_at timestamptz
) AS $$
DECLARE
  norm_q text := lower(unaccent(p_query));
BEGIN
  -- Busca por título, email, telefone
  RETURN QUERY
  SELECT l.id, 'title'::text, l.title, l.created_at
  FROM leads l
  WHERE l.organization_id = p_org_id
    AND l.deleted_at IS NULL
    AND (
      lower(unaccent(l.title)) ILIKE '%' || norm_q || '%'
      OR lower(unaccent(coalesce(l.email,''))) ILIKE '%' || norm_q || '%'
      OR l.phone ILIKE '%' || norm_q || '%'
    )
  LIMIT p_limit;

  -- Busca por conteúdo de mensagens
  RETURN QUERY
  SELECT DISTINCT ON (la.lead_id)
    la.lead_id, 'message'::text,
    left(la.content, 120),
    la.created_at
  FROM lead_activities la
  WHERE la.organization_id = p_org_id
    AND lower(unaccent(coalesce(la.content,''))) ILIKE '%' || norm_q || '%'
    AND la.type IN ('whatsapp','email','note')
  ORDER BY la.lead_id, la.created_at DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FIM DA MIGRAÇÃO
-- ============================================================
