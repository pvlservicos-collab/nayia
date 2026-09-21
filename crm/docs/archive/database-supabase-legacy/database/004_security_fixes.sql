-- =========================================================
-- 004) SECURITY FIXES
-- Fix: function_search_path_mutable (4 functions)
-- Fix: extension_in_public (pg_trgm -> extensions schema)
-- =========================================================

-- Fix 1: Move pg_trgm to extensions schema (recommended by Supabase)
ALTER EXTENSION pg_trgm SET SCHEMA extensions;

-- Fix 2: update_updated_at_column - add SET search_path
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = '';

-- Fix 3: is_org_member - add SET search_path
CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean AS $$
SELECT EXISTS (
  SELECT 1
  FROM public.organization_members
  WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND (status = 'active' OR status = 'invited')
    AND (deleted_at IS NULL)
);
$$ LANGUAGE sql
   SECURITY DEFINER
   SET search_path = '';

-- Fix 4: handle_new_user - add SET search_path
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = '';

-- Fix 5: update_lead_activity_summary - add SET search_path
CREATE OR REPLACE FUNCTION public.update_lead_activity_summary()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.leads
  SET
    last_activity_at = NEW.created_at,
    last_activity_type = NEW.type,
    last_activity_by_member_id = NEW.actor_member_id,
    updated_at = now()
  WHERE id = NEW.lead_id AND organization_id = NEW.organization_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = '';
