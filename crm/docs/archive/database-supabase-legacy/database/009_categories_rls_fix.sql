-- 009_categories_rls_fix.sql
-- Esse script garante que as políticas RLS para custom_field_categories sejam aplicadas corretamente
-- usando DROP POLICY IF EXISTS para evitar erros caso já existam.

ALTER TABLE custom_field_categories ENABLE ROW LEVEL SECURITY;

-- 1. Permissão de leitura (SELECT)
DROP POLICY IF EXISTS "Users can view custom field categories of their organization" ON custom_field_categories;
CREATE POLICY "Users can view custom field categories of their organization"
    ON custom_field_categories FOR SELECT
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));

-- 2. Permissão de inserção (INSERT)
DROP POLICY IF EXISTS "Admins can insert custom field categories" ON custom_field_categories;
CREATE POLICY "Admins can insert custom field categories"
    ON custom_field_categories FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));

-- 3. Permissão de atualização (UPDATE)
DROP POLICY IF EXISTS "Admins can update custom field categories" ON custom_field_categories;
CREATE POLICY "Admins can update custom field categories"
    ON custom_field_categories FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));

-- 4. Permissão de deleção (DELETE)
DROP POLICY IF EXISTS "Admins can delete custom field categories" ON custom_field_categories;
CREATE POLICY "Admins can delete custom field categories"
    ON custom_field_categories FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
    ));
