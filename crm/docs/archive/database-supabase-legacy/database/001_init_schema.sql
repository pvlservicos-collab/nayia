-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For partial string search if needed later

-- =========================================================
-- 0) ENUMS
-- =========================================================
CREATE TYPE member_status AS ENUM ('active', 'invited', 'disabled');
CREATE TYPE integration_status AS ENUM ('active', 'disabled');
CREATE TYPE lead_activity_type AS ENUM ('note', 'call', 'whatsapp', 'email', 'system');
CREATE TYPE custom_field_type AS ENUM ('text', 'number', 'date', 'bool', 'select', 'multi_select', 'json');

-- Trigger function for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- =========================================================
-- 1) ORGANIZAÇÕES E PLANOS
-- =========================================================
CREATE TABLE tiers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    max_users integer,
    can_use_custom_fields boolean DEFAULT false,
    permissions jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    tier_id uuid REFERENCES tiers(id),
    timezone text DEFAULT 'UTC',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz
);

-- Indexes for organizations
CREATE UNIQUE INDEX idx_organizations_name ON organizations(name) WHERE deleted_at IS NULL;
CREATE INDEX idx_organizations_tier_id ON organizations(tier_id);

CREATE TRIGGER update_organizations_modtime BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 2) USUÁRIOS E MATRIZ DE ACESSO
-- =========================================================
-- Profiles usually linked to auth.users, but here we define the table as requested
CREATE TABLE profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, -- Assuming Supabase Auth
    full_name text,
    avatar_url text,
    timezone text,
    is_superadmin boolean DEFAULT false
);

CREATE TABLE organization_roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb,
    version integer DEFAULT 1,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    -- Constraint for composite FKs later
    CONSTRAINT uq_organization_roles_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_org_roles_name ON organization_roles(organization_id, name);
CREATE TRIGGER update_org_roles_modtime BEFORE UPDATE ON organization_roles FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE organization_members (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    user_id uuid NOT NULL REFERENCES profiles(id),
    role_id uuid NOT NULL,
    status member_status DEFAULT 'active',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    -- Composite FK to ensure role belongs to same org
    CONSTRAINT fk_org_members_role FOREIGN KEY (organization_id, role_id) REFERENCES organization_roles(organization_id, id),
    -- Constraint for composite FKs later
    CONSTRAINT uq_organization_members_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_org_members_user ON organization_members(organization_id, user_id) WHERE deleted_at IS NULL;
CREATE TRIGGER update_org_members_modtime BEFORE UPDATE ON organization_members FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 3) PIPELINES E ESTÁGIOS
-- =========================================================
CREATE TABLE pipelines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    -- Constraint for composite FKs later
    CONSTRAINT uq_pipelines_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_pipelines_name ON pipelines(organization_id, name) WHERE deleted_at IS NULL;
CREATE TRIGGER update_pipelines_modtime BEFORE UPDATE ON pipelines FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE pipeline_stages (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL, -- Tenant integrity
    pipeline_id uuid NOT NULL,
    name text NOT NULL,
    color text,
    rank numeric(20, 6) NOT NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    -- Composite FK: pipeline must belong to same org
    CONSTRAINT fk_pipeline_stages_pipeline FOREIGN KEY (organization_id, pipeline_id) REFERENCES pipelines(organization_id, id),
    -- Constraint for composite FKs later
    CONSTRAINT uq_pipeline_stages_org_id UNIQUE (organization_id, id)
);

CREATE INDEX idx_pipeline_stages_rank ON pipeline_stages(pipeline_id, rank) WHERE deleted_at IS NULL;
CREATE TRIGGER update_pipeline_stages_modtime BEFORE UPDATE ON pipeline_stages FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 4) CANAIS E INTEGRAÇÕES
-- =========================================================
CREATE TABLE integrations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    type text,
    config jsonb DEFAULT '{}'::jsonb,
    status integration_status DEFAULT 'active',
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT uq_integrations_org_id UNIQUE (organization_id, id)
);
-- Partial unique index on name if desired, currently just FK index implied
CREATE INDEX idx_integrations_org_name ON integrations(organization_id, name);
CREATE TRIGGER update_integrations_modtime BEFORE UPDATE ON integrations FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 5) CRM CORE (Leads)
-- =========================================================
CREATE TABLE leads (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    stage_id uuid,
    integration_id uuid,
    owner_member_id uuid,
    title text NOT NULL,
    external_id text,
    
    -- Native CRM Fields (Hybrid Model)
    email text,
    phone text, -- NOT NULL can be enforced if desired, but allowing NULL for flexibility initially
    
    -- AI Flags
    ai_interest_level text,
    ai_next_action_short text,
    
    -- Custom Fields
    custom_attributes jsonb DEFAULT '{}'::jsonb,
    
    -- Denormalization
    last_activity_at timestamptz,
    last_activity_type lead_activity_type,
    last_activity_by_member_id uuid,
    
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    
    -- Composite FKs for tenant integrity
    CONSTRAINT fk_leads_stage FOREIGN KEY (organization_id, stage_id) REFERENCES pipeline_stages(organization_id, id),
    CONSTRAINT fk_leads_integration FOREIGN KEY (organization_id, integration_id) REFERENCES integrations(organization_id, id),
    CONSTRAINT fk_leads_owner FOREIGN KEY (organization_id, owner_member_id) REFERENCES organization_members(organization_id, id),
    CONSTRAINT fk_leads_last_activity_by FOREIGN KEY (organization_id, last_activity_by_member_id) REFERENCES organization_members(organization_id, id),
    
    CONSTRAINT uq_leads_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_leads_external_id ON leads(integration_id, external_id) WHERE external_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_leads_stage ON leads(organization_id, stage_id, created_at);
CREATE INDEX idx_leads_owner ON leads(organization_id, owner_member_id);
CREATE INDEX idx_leads_last_activity ON leads(organization_id, last_activity_at);
CREATE INDEX idx_leads_custom_attrs ON leads USING GIN (custom_attributes);
CREATE TRIGGER update_leads_modtime BEFORE UPDATE ON leads FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 6) AI AGENT
-- =========================================================
CREATE TABLE lead_ai_insights (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    ai_summary text,
    ai_metadata jsonb DEFAULT '{}'::jsonb,
    updated_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_ai_insights_lead FOREIGN KEY (organization_id, lead_id) REFERENCES leads(organization_id, id)
);

CREATE UNIQUE INDEX idx_ai_insights_lead ON lead_ai_insights(organization_id, lead_id);
-- No trigger needed for updated_at if we only update it manually, but good practice to have one
CREATE TRIGGER update_ai_insights_modtime BEFORE UPDATE ON lead_ai_insights FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 7) HISTÓRICO E ATIVIDADES
-- =========================================================
CREATE TABLE lead_stage_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    from_stage_id uuid,
    to_stage_id uuid,
    changed_by_member_id uuid,
    changed_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_history_lead FOREIGN KEY (organization_id, lead_id) REFERENCES leads(organization_id, id),
    CONSTRAINT fk_history_from_stage FOREIGN KEY (organization_id, from_stage_id) REFERENCES pipeline_stages(organization_id, id),
    CONSTRAINT fk_history_to_stage FOREIGN KEY (organization_id, to_stage_id) REFERENCES pipeline_stages(organization_id, id),
    CONSTRAINT fk_history_actor FOREIGN KEY (organization_id, changed_by_member_id) REFERENCES organization_members(organization_id, id)
);

CREATE INDEX idx_stage_history_lead ON lead_stage_history(lead_id, changed_at);

CREATE TABLE lead_activities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    actor_member_id uuid,
    type lead_activity_type,
    content text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_activities_lead FOREIGN KEY (organization_id, lead_id) REFERENCES leads(organization_id, id),
    CONSTRAINT fk_activities_actor FOREIGN KEY (organization_id, actor_member_id) REFERENCES organization_members(organization_id, id)
);

CREATE INDEX idx_activities_lead ON lead_activities(lead_id, created_at DESC);

-- =========================================================
-- 8) CUSTOM FIELDS
-- =========================================================
CREATE TABLE custom_field_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    key text NOT NULL,
    name text NOT NULL,
    field_type custom_field_type NOT NULL,
    schema jsonb DEFAULT '{}'::jsonb,
    is_indexed boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    
    CONSTRAINT uq_custom_field_defs_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_custom_fields_key ON custom_field_definitions(organization_id, key) WHERE deleted_at IS NULL;
CREATE TRIGGER update_custom_fields_modtime BEFORE UPDATE ON custom_field_definitions FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE custom_field_index_values (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    field_id uuid NOT NULL,
    value_text text,
    value_number numeric,
    value_date date,
    value_bool boolean,
    value_json jsonb,
    updated_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_index_lead FOREIGN KEY (organization_id, lead_id) REFERENCES leads(organization_id, id),
    CONSTRAINT fk_index_field FOREIGN KEY (organization_id, field_id) REFERENCES custom_field_definitions(organization_id, id)
);

CREATE UNIQUE INDEX idx_field_index_unique ON custom_field_index_values(lead_id, field_id);
-- Specific indexes for values
CREATE INDEX idx_field_index_num ON custom_field_index_values(field_id, value_number);
CREATE INDEX idx_field_index_date ON custom_field_index_values(field_id, value_date);
CREATE INDEX idx_field_index_text ON custom_field_index_values(field_id, value_text);
CREATE TRIGGER update_field_index_modtime BEFORE UPDATE ON custom_field_index_values FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- =========================================================
-- 9) TAGS
-- =========================================================
CREATE TABLE tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    color text,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    deleted_at timestamptz,
    
    CONSTRAINT uq_tags_org_id UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX idx_tags_name ON tags(organization_id, name) WHERE deleted_at IS NULL;
CREATE TRIGGER update_tags_modtime BEFORE UPDATE ON tags FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE lead_tags (
    organization_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    
    PRIMARY KEY (organization_id, lead_id, tag_id),
    CONSTRAINT fk_lead_tags_lead FOREIGN KEY (organization_id, lead_id) REFERENCES leads(organization_id, id),
    CONSTRAINT fk_lead_tags_tag FOREIGN KEY (organization_id, tag_id) REFERENCES tags(organization_id, id)
);

-- =========================================================
-- 10) UI, SEGURANÇA, NOTIFICAÇÕES
-- =========================================================
CREATE TABLE ui_state_drafts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    member_id uuid NOT NULL,
    page_slug text NOT NULL,
    draft_data jsonb,
    updated_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_drafts_member FOREIGN KEY (organization_id, member_id) REFERENCES organization_members(organization_id, id)
);

CREATE UNIQUE INDEX idx_drafts_unique ON ui_state_drafts(organization_id, member_id, page_slug);
CREATE TRIGGER update_drafts_modtime BEFORE UPDATE ON ui_state_drafts FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    actor_member_id uuid,
    action text NOT NULL,
    entity_type text,
    entity_id uuid,
    old_values jsonb,
    new_values jsonb,
    created_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_audit_actor FOREIGN KEY (organization_id, actor_member_id) REFERENCES organization_members(organization_id, id)
);

CREATE INDEX idx_audit_time ON audit_logs(organization_id, created_at);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);

CREATE TABLE notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    recipient_member_id uuid NOT NULL,
    actor_member_id uuid,
    type text,
    title text,
    content text,
    link_url text,
    is_read boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    
    CONSTRAINT fk_notif_recipient FOREIGN KEY (organization_id, recipient_member_id) REFERENCES organization_members(organization_id, id),
    CONSTRAINT fk_notif_actor FOREIGN KEY (organization_id, actor_member_id) REFERENCES organization_members(organization_id, id)
);

CREATE INDEX idx_notif_recipient ON notifications(recipient_member_id, is_read, created_at);

-- =========================================================
-- 11) PREFERÊNCIAS E AUTOMAÇÕES
-- =========================================================
CREATE TABLE user_notification_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id uuid NOT NULL REFERENCES organization_members(id), -- Simple FK as it's 1:1 with member PK
    new_lead_alert boolean DEFAULT true,
    last_stage_alert boolean DEFAULT true,
    no_response_24h_alert boolean DEFAULT true,
    updated_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX idx_notif_settings_member ON user_notification_settings(member_id);
CREATE TRIGGER update_notif_settings_modtime BEFORE UPDATE ON user_notification_settings FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

CREATE TABLE automation_settings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    key text NOT NULL,
    is_enabled boolean DEFAULT false,
    variables jsonb DEFAULT '{}'::jsonb,
    updated_at timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX idx_automations_key ON automation_settings(organization_id, key);
CREATE TRIGGER update_automations_modtime BEFORE UPDATE ON automation_settings FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
