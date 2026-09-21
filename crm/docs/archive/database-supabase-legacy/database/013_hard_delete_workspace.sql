-- =========================================================
-- 013) HARD DELETE WORKSPACE PROCEDURE
-- Creates a stored procedure to forcefully delete an organization
-- and all its associated tenant data.
-- This bypasses the lack of ON DELETE CASCADE in the schema.
-- =========================================================

CREATE OR REPLACE FUNCTION delete_organization_cascade(org_uuid uuid)
RETURNS void AS $$
BEGIN
    -- 1) Delete data that references member_id
    DELETE FROM public.user_notification_settings 
    WHERE member_id IN (SELECT id FROM public.organization_members WHERE organization_id = org_uuid);

    -- 2) Delete setup tokens
    DELETE FROM public.setup_tokens WHERE org_id = org_uuid;

    -- 3) Delete lead related data
    DELETE FROM public.lead_activities WHERE organization_id = org_uuid;
    DELETE FROM public.lead_stage_history WHERE organization_id = org_uuid;
    DELETE FROM public.lead_ai_insights WHERE organization_id = org_uuid;
    DELETE FROM public.lead_tags WHERE organization_id = org_uuid;
    DELETE FROM public.custom_field_index_values WHERE organization_id = org_uuid;
    DELETE FROM public.leads WHERE organization_id = org_uuid;

    -- 4) Delete global org related data
    DELETE FROM public.ui_state_drafts WHERE organization_id = org_uuid;
    DELETE FROM public.audit_logs WHERE organization_id = org_uuid;
    DELETE FROM public.notifications WHERE organization_id = org_uuid;
    DELETE FROM public.automation_settings WHERE organization_id = org_uuid;
    
    DELETE FROM public.tags WHERE organization_id = org_uuid;
    DELETE FROM public.custom_field_definitions WHERE organization_id = org_uuid;
    DELETE FROM public.integrations WHERE organization_id = org_uuid;
    
    -- 5) Delete pipelines
    DELETE FROM public.pipeline_stages WHERE organization_id = org_uuid;
    DELETE FROM public.pipelines WHERE organization_id = org_uuid;

    -- 7) Delete members and roles
    DELETE FROM public.organization_members WHERE organization_id = org_uuid;
    DELETE FROM public.organization_roles WHERE organization_id = org_uuid;

    -- 8) Finally delete the organization itself
    DELETE FROM public.organizations WHERE id = org_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
