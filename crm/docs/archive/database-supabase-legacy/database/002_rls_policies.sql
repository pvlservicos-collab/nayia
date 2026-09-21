-- =========================================================
-- ROW LEVEL SECURITY POLICIES
-- =========================================================

-- Enable RLS on all tables
ALTER TABLE tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE pipeline_stages ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_stage_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_field_index_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE lead_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_state_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notification_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_settings ENABLE ROW LEVEL SECURITY;

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================
-- Check if current user is a member of the given organization
CREATE OR REPLACE FUNCTION is_org_member(org_id uuid)
RETURNS boolean AS $$
SELECT EXISTS (
  SELECT 1
  FROM organization_members
  WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND (status = 'active' OR status = 'invited') 
    AND (deleted_at IS NULL)
) OR EXISTS (
  SELECT 1 
  FROM profiles 
  WHERE id = auth.uid() AND is_superadmin = true
);
$$ LANGUAGE sql SECURITY DEFINER;

-- =========================================================
-- POLICIES
-- =========================================================

-- 1. TIERS (Public read, System write)
CREATE POLICY "Tiers are viewable by everyone" ON tiers FOR SELECT USING (true);

-- 2. PROFILES (Users can read/update their own)
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);

-- 3. ORGANIZATIONS
CREATE POLICY "Members can view their organizations" ON organizations
FOR SELECT USING (is_org_member(id));

-- 4. ORGANIZATION MEMBERS
-- View: Members can view their own membership
CREATE POLICY "Users can view their own membership" ON organization_members
FOR SELECT USING (user_id = auth.uid());

-- View: Members can view other members in their orgs
CREATE POLICY "Members can view other members in same org" ON organization_members
FOR SELECT USING (is_org_member(organization_id));

-- 5. ORGANIZATION ROLES
CREATE POLICY "Members can view roles in their org" ON organization_roles
FOR SELECT USING (is_org_member(organization_id));

-- 6. PIPELINES & STAGES
CREATE POLICY "Members can view pipelines" ON pipelines
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can insert pipelines" ON pipelines
FOR INSERT WITH CHECK (is_org_member(organization_id));

CREATE POLICY "Members can update pipelines" ON pipelines
FOR UPDATE USING (is_org_member(organization_id));

CREATE POLICY "Members can delete pipelines" ON pipelines
FOR DELETE USING (is_org_member(organization_id));

CREATE POLICY "Members can view stages" ON pipeline_stages
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can insert stages" ON pipeline_stages
FOR INSERT WITH CHECK (is_org_member(organization_id));

CREATE POLICY "Members can update stages" ON pipeline_stages
FOR UPDATE USING (is_org_member(organization_id));

CREATE POLICY "Members can delete stages" ON pipeline_stages
FOR DELETE USING (is_org_member(organization_id));

-- 7. INTEGRATIONS
CREATE POLICY "Members can view integrations" ON integrations
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can insert integrations" ON integrations
FOR INSERT WITH CHECK (is_org_member(organization_id));

CREATE POLICY "Members can update integrations" ON integrations
FOR UPDATE USING (is_org_member(organization_id));

CREATE POLICY "Members can delete integrations" ON integrations
FOR DELETE USING (is_org_member(organization_id));

-- 8. LEADS (Core Isolation)
CREATE POLICY "Members can view leads" ON leads
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can create leads" ON leads
FOR INSERT WITH CHECK (is_org_member(organization_id));

CREATE POLICY "Members can update leads" ON leads
FOR UPDATE USING (is_org_member(organization_id));

-- 9. AI INSIGHTS
CREATE POLICY "Members can view ai insights" ON lead_ai_insights
FOR SELECT USING (is_org_member(organization_id));

-- 10. HISTORY & ACTIVITIES
CREATE POLICY "Members can view history" ON lead_stage_history
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can view activities" ON lead_activities
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can create activities" ON lead_activities
FOR INSERT WITH CHECK (is_org_member(organization_id));

-- 11. CUSTOM FIELDS
CREATE POLICY "Members can view field definitions" ON custom_field_definitions
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can view field values" ON custom_field_index_values
FOR SELECT USING (is_org_member(organization_id));

-- 12. TAGS
CREATE POLICY "Members can view tags" ON tags
FOR SELECT USING (is_org_member(organization_id));

CREATE POLICY "Members can view lead tags" ON lead_tags
FOR SELECT USING (is_org_member(organization_id));

-- 13. UI DRAFTS (Personal)
CREATE POLICY "Users view own drafts" ON ui_state_drafts
FOR SELECT USING (auth.uid() = (SELECT user_id FROM organization_members WHERE id = member_id));

CREATE POLICY "Users manage own drafts" ON ui_state_drafts
FOR ALL USING (auth.uid() = (SELECT user_id FROM organization_members WHERE id = member_id));

-- 14. AUDIT LOGS
CREATE POLICY "Members view org audit logs" ON audit_logs
FOR SELECT USING (is_org_member(organization_id));

-- 15. NOTIFICATIONS
CREATE POLICY "Users view own notifications" ON notifications
FOR SELECT USING (
    recipient_member_id IN (
        SELECT id FROM organization_members WHERE user_id = auth.uid()
    )
);

-- 16. SETTINGS
CREATE POLICY "Users manage own notification settings" ON user_notification_settings
FOR ALL USING (
    member_id IN (
        SELECT id FROM organization_members WHERE user_id = auth.uid()
    )
);

CREATE POLICY "Members view automation settings" ON automation_settings
FOR SELECT USING (is_org_member(organization_id));
