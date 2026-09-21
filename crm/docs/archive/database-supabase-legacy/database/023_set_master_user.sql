-- 1. Ensure the user is marked as superadmin in the profiles table
UPDATE public.profiles
SET is_superadmin = true
WHERE id = (
    SELECT id 
    FROM auth.users 
    WHERE email = 'marcos@atlaseye.com.br'
);

-- 2. Re-apply the RLS policy on organizations to guarantee superadmins can read all.
-- This prevents recursion loops by checking profiles directly.
DROP POLICY IF EXISTS "Members can view their organizations" ON public.organizations;

CREATE POLICY "Members can view their organizations" 
  ON public.organizations
  FOR SELECT 
  USING (
    id IN (SELECT organization_id FROM public.organization_members WHERE user_id = auth.uid())
    OR 
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_superadmin = true)
  );
