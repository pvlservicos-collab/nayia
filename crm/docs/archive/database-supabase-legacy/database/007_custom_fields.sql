-- 007_custom_fields.sql

-- 1. Add new enum values for custom_field_type
ALTER TYPE custom_field_type ADD VALUE IF NOT EXISTS 'currency';
ALTER TYPE custom_field_type ADD VALUE IF NOT EXISTS 'datetime';

-- 2. Create the custom_field_categories table
CREATE TABLE IF NOT EXISTS custom_field_categories (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES organizations(id),
    name text NOT NULL,
    rank numeric(20, 6) DEFAULT 0,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    
    CONSTRAINT uq_cf_categories_org_id UNIQUE (organization_id, id)
);

-- Trigger for updated_at on categories (assuming the function already exists from 001_init_schema)
CREATE TRIGGER update_cf_categories_modtime BEFORE UPDATE ON custom_field_categories FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();

-- 3. Update custom_field_definitions to link to categories
ALTER TABLE custom_field_definitions
ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES custom_field_categories(id) ON DELETE SET NULL;

-- 4. RLS Policies for custom_field_categories
ALTER TABLE custom_field_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view custom field categories of their organization"
    ON custom_field_categories FOR SELECT
    USING (organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid() AND deleted_at IS NULL
    ));

CREATE POLICY "Admins can insert custom field categories"
    ON custom_field_categories FOR INSERT
    WITH CHECK (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));

CREATE POLICY "Admins can update custom field categories"
    ON custom_field_categories FOR UPDATE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));

CREATE POLICY "Admins can delete custom field categories"
    ON custom_field_categories FOR DELETE
    USING (organization_id IN (
        SELECT organization_id FROM organization_members 
        WHERE user_id = auth.uid() 
        AND deleted_at IS NULL
        AND role_id IN (SELECT id FROM organization_roles WHERE permissions->>'manage_settings' = 'true')
    ));
