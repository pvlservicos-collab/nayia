-- File: 019_fix_is_org_member_final.sql

-- 1. Create a definitive version of is_org_member 
-- The problem with the previous PLPGSQL function might have been that the `profiles` check caused a recursion if profiles RLS also used is_org_member (it doesn't, though).
-- Or `organization_members` RLS uses `is_org_member(organization_id)` on SELECT. 
-- When `is_org_member` looks into `organization_members`, RLS triggers again -> calls `is_org_member` -> looks into `organization_members` -> infinite recursion!
-- PostgreSQL 15+ breaks the loop internally or halts with an error, hiding all rows.

-- Fix: We bypass RLS inside the function by calling it as SECURITY DEFINER and ensuring search_path is set so it works safely.
-- BUT, if the function is owned by a generic user, SECURITY DEFINER doesn't bypass RLS.
-- Therefore, we must define it this way:

ALTER FUNCTION public.is_org_member(uuid) OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  -- O dono postgres vai ignorar o RLS e ler as tabelas puras:
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

-- 2. Prevent recursion in organization_members:
-- The policy "Users can view their own membership" might be calling `is_org_member(organization_id)`.
-- Let's drop it and recreate it properly.

DROP POLICY IF EXISTS "Users can view their own membership" ON public.organization_members;
CREATE POLICY "Users can view their own membership" 
  ON public.organization_members 
  FOR SELECT 
  USING (
    user_id = auth.uid() 
    OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true)
  );

-- Also fix "Members can view all memberships in their orgs"
DROP POLICY IF EXISTS "Members can view all memberships in their orgs" ON public.organization_members;
CREATE POLICY "Members can view all memberships in their orgs"
  ON public.organization_members
  FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid() AND (status='active' OR status='invited') AND deleted_at IS NULL
    )
    OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true)
  );
