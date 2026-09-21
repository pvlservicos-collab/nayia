-- =========================================================
-- 019) FIX DEFINITIVO: is_org_member e Recursão RLS
-- Removemos o search_path problemático e garantimos que 
-- SECURITY DEFINER seja executado pelo dono correto e 
-- não seja afetado por recursões do RLS em organization_members.
-- =========================================================

-- 1. Redefinir a função de forma ultra robusta
CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND is_superadmin = true
  ) OR EXISTS (
    SELECT 1
    FROM public.organization_members
    WHERE organization_id = org_id
      AND user_id = auth.uid()
      AND (status = 'active' OR status = 'invited') 
      AND (deleted_at IS NULL)
  );
$$;

-- 2. Garantir que a função pertença ao superuser (postgres) para ignorar RLS nas tabelas lidas:
ALTER FUNCTION public.is_org_member(uuid) OWNER TO postgres;

-- 3. (OPCIONAL mas recomendado) Corrigir recursão RLS:
-- Se a tabela organization_members tem RLS que chama is_org_member(), isso gera dependência circular.
-- Apenas os usuários deveriam ver as próprias memberships se não usarmos o bypass da função:
DROP POLICY IF EXISTS "Users can view their own membership" ON public.organization_members;
CREATE POLICY "Users can view their own membership" 
  ON public.organization_members 
  FOR SELECT 
  USING (auth.uid() = user_id OR EXISTS (
     SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true
  ));
