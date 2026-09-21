-- =========================================================
-- PARTE 3: SCRIPT DE SEGURANÇA PARA CARGOS
-- (Organization Roles)
-- =========================================================

-- Limpando Políticas Antigas
DROP POLICY IF EXISTS "Members can view roles in their org" ON public.organization_roles;
DROP POLICY IF EXISTS "Members can insert roles" ON public.organization_roles;
DROP POLICY IF EXISTS "Members can update roles" ON public.organization_roles;
DROP POLICY IF EXISTS "Members can delete roles" ON public.organization_roles;

-- RECRIANDO COM A ARQUITETURA LIVRE DE LOOP (auth_get_user_orgs)

-- ================ ORGANIZATION ROLES ================
ALTER TABLE public.organization_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Roles view rule" ON public.organization_roles FOR SELECT USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Roles insert rule" ON public.organization_roles FOR INSERT WITH CHECK (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Roles update rule" ON public.organization_roles FOR UPDATE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
CREATE POLICY "Roles delete rule" ON public.organization_roles FOR DELETE USING (organization_id IN (SELECT public.auth_get_user_orgs()) OR public.auth_is_superadmin());
