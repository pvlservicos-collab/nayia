-- Restaura o search_path da função is_org_member para "public"
-- para corrigir erros de permissão onde a função auth.uid()
-- não conseguia ser resolvida corretamente no contexto de RLS.

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
   SET search_path = public;
