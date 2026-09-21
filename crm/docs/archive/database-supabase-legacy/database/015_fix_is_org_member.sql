-- =========================================================
-- 015) FIX: is_org_member
-- Restaura a permissão de superadmin que foi removida no 
-- script de segurança anterior e faz com que o admin
-- possa ver todas as organizações novamente.
-- =========================================================

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean AS $$
SELECT EXISTS (
  SELECT 1
  FROM public.organization_members
  WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND (status = 'active' OR status = 'invited') 
    AND (deleted_at IS NULL)
) OR EXISTS (
  SELECT 1 
  FROM public.profiles 
  WHERE id = auth.uid() AND is_superadmin = true
);
$$ LANGUAGE sql
   SECURITY DEFINER
   SET search_path = '';
