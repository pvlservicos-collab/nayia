-- Resolução de problemas RLS:
-- Restaurar tudo ao estado mais simples possível para não bloquear o superadmin.

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM profiles
    WHERE id = auth.uid() AND is_superadmin = true
  ) OR EXISTS (
    SELECT 1
    FROM organization_members
    WHERE organization_id = org_id
      AND user_id = auth.uid()
      AND (status = 'active' OR status = 'invited') 
      AND (deleted_at IS NULL)
  );
$$;

-- O RLS nas tabelas pode estar causando um loop que inviabiliza as checagens. 
-- Para a tabela `profiles`, o admin PRECISA conseguir ler seu próprio is_superadmin.
-- A politica original era:
-- CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
-- Isso é ok.

-- Para `organization_members`, se existir RLS, ele PRECISA permitir o próprio usuário ler.
-- As regras antigas usavam `is_org_member`. Isso DEVE ser removido aqui para garantir!
DROP POLICY IF EXISTS "Members can view other members in same org" ON public.organization_members;
DROP POLICY IF EXISTS "Users can view their own membership" ON public.organization_members;
DROP POLICY IF EXISTS "Members can view all memberships in their orgs" ON public.organization_members;

-- Substituir por regras livres de loops:
CREATE POLICY "Users can view their own membership" 
ON public.organization_members FOR SELECT 
USING (user_id = auth.uid());

CREATE POLICY "Superadmins can view all memberships" 
ON public.organization_members FOR SELECT 
USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true));

-- Permitir que membros de uma org vejam os demais da org, MAS sem chamar is_org_member(), para não criar loop!
CREATE POLICY "Members view peers" 
ON public.organization_members FOR SELECT 
USING (
  organization_id IN (
    SELECT organization_id 
    FROM public.organization_members AS my_orgs 
    WHERE my_orgs.user_id = auth.uid()
  )
);
