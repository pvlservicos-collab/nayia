-- =========================================================
-- DIAGNÓSTICO DE RLS POLICIES
-- =========================================================
-- Execute este script no SQL Editor para verificar se as
-- policies foram criadas corretamente.
-- =========================================================

-- 1. Verificar se RLS está habilitado nas tabelas
SELECT
    schemaname,
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables
WHERE schemaname = 'public'
    AND tablename IN ('organizations', 'pipelines', 'pipeline_stages', 'leads', 'organization_members', 'profiles', 'tags', 'lead_tags', 'lead_activities', 'lead_stage_history', 'tiers', 'organization_roles')
ORDER BY tablename;

-- 2. Listar todas as policies criadas
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
    AND tablename IN ('organizations', 'pipelines', 'pipeline_stages', 'leads', 'organization_members', 'profiles', 'tags', 'lead_tags', 'lead_activities', 'lead_stage_history', 'tiers', 'organization_roles')
ORDER BY tablename, policyname;

-- 3. Contar policies por tabela
SELECT
    tablename,
    COUNT(*) as policy_count
FROM pg_policies
WHERE schemaname = 'public'
    AND tablename IN ('organizations', 'pipelines', 'pipeline_stages', 'leads', 'organization_members', 'profiles', 'tags', 'lead_tags', 'lead_activities', 'lead_stage_history', 'tiers', 'organization_roles')
GROUP BY tablename
ORDER BY tablename;

-- 4. Verificar se as DEV policies foram criadas
SELECT
    tablename,
    policyname
FROM pg_policies
WHERE schemaname = 'public'
    AND policyname LIKE 'dev_%'
ORDER BY tablename, policyname;

-- =========================================================
-- Resultado esperado:
--
-- Query 1: Todas as tabelas devem ter rls_enabled = true
--
-- Query 4: Deve listar as dev policies:
--   - dev_read_organizations
--   - dev_read_pipelines
--   - dev_read_pipeline_stages
--   - dev_read_leads
--   - dev_read_org_members
--   - dev_read_profiles
--   - dev_read_tags
--   - dev_read_lead_tags
--   - dev_read_activities
--   - dev_read_stage_history
--   - dev_read_tiers
--   - dev_read_org_roles
--   - dev_write_leads
--   - dev_write_stage_history
--   - dev_write_activities
-- =========================================================
