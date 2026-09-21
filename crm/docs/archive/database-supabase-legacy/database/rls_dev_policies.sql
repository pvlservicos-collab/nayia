-- =========================================================
-- ATLAS EYE CRM — RLS POLICIES (Desenvolvimento)
-- =========================================================
-- Execute este script no SQL Editor do Supabase para permitir
-- que a anon key consiga ler os dados durante desenvolvimento.
-- =========================================================

-- Habilitar RLS (necessário para policies funcionarem)
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipeline_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_stage_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE tiers ENABLE ROW LEVEL SECURITY;

-- Policies de leitura para desenvolvimento (anon + authenticated)
DROP POLICY IF EXISTS "dev_read_organizations" ON organizations;
CREATE POLICY "dev_read_organizations" ON organizations FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_org_members" ON organization_members;
CREATE POLICY "dev_read_org_members" ON organization_members FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_org_roles" ON organization_roles;
CREATE POLICY "dev_read_org_roles" ON organization_roles FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_profiles" ON profiles;
CREATE POLICY "dev_read_profiles" ON profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_pipelines" ON pipelines;
CREATE POLICY "dev_read_pipelines" ON pipelines FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_pipeline_stages" ON pipeline_stages;
CREATE POLICY "dev_read_pipeline_stages" ON pipeline_stages FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_leads" ON leads;
CREATE POLICY "dev_read_leads" ON leads FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_activities" ON lead_activities;
CREATE POLICY "dev_read_activities" ON lead_activities FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_stage_history" ON lead_stage_history;
CREATE POLICY "dev_read_stage_history" ON lead_stage_history FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_lead_tags" ON lead_tags;
CREATE POLICY "dev_read_lead_tags" ON lead_tags FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_tags" ON tags;
CREATE POLICY "dev_read_tags" ON tags FOR SELECT USING (true);

DROP POLICY IF EXISTS "dev_read_tiers" ON tiers;
CREATE POLICY "dev_read_tiers" ON tiers FOR SELECT USING (true);

-- Policies de escrita para desenvolvimento (para drag-and-drop, etc.)
DROP POLICY IF EXISTS "dev_write_leads" ON leads;
CREATE POLICY "dev_write_leads" ON leads FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "dev_write_stage_history" ON lead_stage_history;
CREATE POLICY "dev_write_stage_history" ON lead_stage_history FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "dev_write_activities" ON lead_activities;
CREATE POLICY "dev_write_activities" ON lead_activities FOR INSERT WITH CHECK (true);

-- =========================================================
-- DONE! Agora a anon key consegue ler e escrever dados.
-- ⚠️ Em produção, substituir por policies baseadas em auth.uid()
-- =========================================================
