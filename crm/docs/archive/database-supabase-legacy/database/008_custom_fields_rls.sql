-- 008_custom_fields_rls.sql

-- 1. Policies for custom_field_definitions
-- (SELECT policy already exists in 002_rls_policies.sql)

DROP POLICY IF EXISTS "Admins can insert field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can insert field definitions"
    ON custom_field_definitions FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));

DROP POLICY IF EXISTS "Admins can update field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can update field definitions"
    ON custom_field_definitions FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));

DROP POLICY IF EXISTS "Admins can delete field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can delete field definitions"
    ON custom_field_definitions FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));

-- 2. Policies for custom_field_index_values
-- (SELECT policy already exists in 002_rls_policies.sql)

DROP POLICY IF EXISTS "Members can insert field values" ON custom_field_index_values;
CREATE POLICY "Members can insert field values"
    ON custom_field_index_values FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));

DROP POLICY IF EXISTS "Members can update field values" ON custom_field_index_values;
CREATE POLICY "Members can update field values"
    ON custom_field_index_values FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));

DROP POLICY IF EXISTS "Members can delete field values" ON custom_field_index_values;
CREATE POLICY "Members can delete field values"
    ON custom_field_index_values FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));
