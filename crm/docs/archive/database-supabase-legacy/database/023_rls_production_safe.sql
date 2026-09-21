-- =========================================================
-- SCRIPT MESTRE DE SEGURANÇA E PERFORMANCE PARA PRODUÇÃO
-- Resolve o erro "RLS Infinite Recursion" oculto
-- =========================================================

-- 1. CRIANDO AS FUNÇÕES-NÚCLEO ISOLADAS DE RLS
-- Estas funções leem o banco de forma direta, sem acionar
-- o RLS delas próprias. (SECURITY DEFINER + search_path setado)

CREATE OR REPLACE FUNCTION public.auth_is_superadmin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND is_superadmin = true
  );
$$;
ALTER FUNCTION public.auth_is_superadmin() OWNER TO postgres;


CREATE OR REPLACE FUNCTION public.auth_get_user_orgs()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT organization_id 
  FROM public.organization_members
  WHERE user_id = auth.uid()
    AND status IN ('active', 'invited')
    AND deleted_at IS NULL;
$$;
ALTER FUNCTION public.auth_get_user_orgs() OWNER TO postgres;


-- 2. LIMPANDO O CAOS DO RLS ATUAL
-- Limpando completamente políticas recursivas ou colapsadas
-- (NÃO vai apagar seus dados, apenas as regras de permissão velhas)

DROP POLICY IF EXISTS "Members can view their organizations" ON public.organizations;

DROP POLICY IF EXISTS "Users can view their own membership" ON public.organization_members;
DROP POLICY IF EXISTS "Members can view other members in same org" ON public.organization_members;
DROP POLICY IF EXISTS "Members can view all memberships in their orgs" ON public.organization_members;
DROP POLICY IF EXISTS "Superadmins can view all memberships" ON public.organization_members;
DROP POLICY IF EXISTS "Members view peers in same org" ON public.organization_members;

DROP POLICY IF EXISTS "Members can view pipelines" ON public.pipelines;
DROP POLICY IF EXISTS "Members can insert pipelines" ON public.pipelines;
DROP POLICY IF EXISTS "Members can update pipelines" ON public.pipelines;
DROP POLICY IF EXISTS "Members can delete pipelines" ON public.pipelines;

DROP POLICY IF EXISTS "Members can view stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Members can insert stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Members can update stages" ON public.pipeline_stages;
DROP POLICY IF EXISTS "Members can delete stages" ON public.pipeline_stages;


-- 3. RECRIANDO AS POLÍTICAS SIMPLES COM AS NOVAS FUNÇÕES PERFEITAS
-- Qualquer superadmin OU membro autorizado passará sem gerar Loops de leitura!

-- ================ ORGANIZATIONS ================
CREATE POLICY "Orgs view rule" ON public.organizations FOR SELECT
USING (id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ MEMBERS ================
CREATE POLICY "Members view rule" ON public.organization_members FOR SELECT
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ PIPELINES ================
CREATE POLICY "Pipelines view rule" ON public.pipelines FOR SELECT
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Pipelines insert rule" ON public.pipelines FOR INSERT
WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Pipelines update rule" ON public.pipelines FOR UPDATE
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Pipelines delete rule" ON public.pipelines FOR DELETE
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

-- ================ STAGES ================
CREATE POLICY "Stages view rule" ON public.pipeline_stages FOR SELECT
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Stages insert rule" ON public.pipeline_stages FOR INSERT
WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Stages update rule" ON public.pipeline_stages FOR UPDATE
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());

CREATE POLICY "Stages delete rule" ON public.pipeline_stages FOR DELETE
USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
