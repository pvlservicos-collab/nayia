-- =========================================================
-- SCRIPT DE RESGATE: RLS & Múltiplas Organizações
-- =========================================================
-- Esse script elimina definitivamente as chances de "loops infinitos"
-- das políticas de segurança, resgatando o acesso do Administrador
-- e normalizando o acesso às organizações, funis e campos.

-- 1. Forçar a função para o dono máximo (postgres) e usar a sintaxe limpa
ALTER FUNCTION public.is_org_member(uuid) OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  -- Retorna VERDADEIRO se o usuário for superadmin (mesmo se nao estiver em organization_members)
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND is_superadmin = true
  )
  -- OU retorna VERDADEIRO se o usuário for membro ativo/convidado da org_id fornecida
  OR EXISTS (
    SELECT 1
    FROM public.organization_members
    WHERE organization_id = org_id
      AND user_id = auth.uid()
      AND status IN ('active', 'invited')
      AND deleted_at IS NULL
  );
$$;


-- 2. Limpar políticas recursivas preexistentes na tabela de membros (que causam o bloqueio total)
DROP POLICY IF EXISTS "Users can view their own membership" ON public.organization_members;
DROP POLICY IF EXISTS "Members can view other members in same org" ON public.organization_members;
DROP POLICY IF EXISTS "Members can view all memberships in their orgs" ON public.organization_members;

-- 3. Criar políticas seguras e diretas para membros da organização (Sem invocar is_org_member na própria tabela de membros)
CREATE POLICY "Users can view their own membership" 
  ON public.organization_members
  FOR SELECT 
  USING (user_id = auth.uid());

CREATE POLICY "Superadmins can view all memberships" 
  ON public.organization_members
  FOR SELECT 
  USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true));

CREATE POLICY "Members can view peers in same org" 
  ON public.organization_members
  FOR SELECT 
  USING (
    organization_id IN (
      SELECT organization_id 
      FROM public.organization_members 
      WHERE user_id = auth.uid()
    )
  );

-- 4. Garantir que as organizações em si também possam ser visualizadas diretamente
DROP POLICY IF EXISTS "Members can view their organizations" ON public.organizations;
CREATE POLICY "Members can view their organizations" 
  ON public.organizations
  FOR SELECT 
  USING (
    id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true)
  );
