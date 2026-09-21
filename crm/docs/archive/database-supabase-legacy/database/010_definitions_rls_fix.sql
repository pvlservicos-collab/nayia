-- 010_definitions_rls_fix.sql
-- Esse script garante que as políticas RLS para custom_field_definitions sejam aplicadas corretamente,
-- relaxando a restrição de role_id temporariamente ou de forma condizente com a correção de categories.

ALTER TABLE custom_field_definitions ENABLE ROW LEVEL SECURITY;

-- 1. Permissão de leitura (SELECT) - já deve existir mas garantimos
DROP POLICY IF EXISTS "Users can view custom field definitions of their organization" ON custom_field_definitions;
CREATE POLICY "Users can view custom field definitions of their organization"
    ON custom_field_definitions FOR SELECT
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));

-- 2. Permissão de inserção (INSERT)
DROP POLICY IF EXISTS "Admins can insert field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can insert field definitions"
    ON custom_field_definitions FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));

-- 3. Permissão de atualização (UPDATE)
DROP POLICY IF EXISTS "Admins can update field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can update field definitions"
    ON custom_field_definitions FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));

-- 4. Permissão de deleção (DELETE)
DROP POLICY IF EXISTS "Admins can delete field definitions" ON custom_field_definitions;
CREATE POLICY "Admins can delete field definitions"
    ON custom_field_definitions FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));
