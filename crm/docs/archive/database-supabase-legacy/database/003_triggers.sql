-- =========================================================
-- TRIGGER: Handle New User (Auth -> Profile)
-- =========================================================
-- Automatically polls data from auth.users to public.profiles
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users (Requires Supabase Admin privileges to apply, but defined here for plan)
-- CREATE TRIGGER on_auth_user_created
--   AFTER INSERT ON auth.users
--   FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- =========================================================
-- TRIGGER: Update Lead Last Activity
-- =========================================================
-- "Na inserção de activity, atualizar leads.last_activity_* via trigger."
CREATE OR REPLACE FUNCTION update_lead_activity_summary()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE leads
  SET 
    last_activity_at = NEW.created_at,
    last_activity_type = NEW.type,
    last_activity_by_member_id = NEW.actor_member_id,
    updated_at = now()
  WHERE id = NEW.lead_id AND organization_id = NEW.organization_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_activity_created
  AFTER INSERT ON lead_activities
  FOR EACH ROW
  EXECUTE PROCEDURE update_lead_activity_summary();


-- =========================================================
-- TRIGGER: Sync Custom Fields (Placeholder Strategy)
-- =========================================================
-- Logic: When leads.custom_attributes changes, update custom_field_index_values.
-- This is complex to do purely in SQL due to JSON typing, but here is the stub.
-- Implementation recommendation: Handle this in the Application Layer (Edge Function or Service) 
-- to avoid heavy JSON parsing in the DB trigger affecting write performance.

-- =========================================================
-- TRIGGER: Handle New Organization (Create Default Pipeline)
-- =========================================================
-- Automatically creates a default pipeline and 5 stages when a new org is created
CREATE OR REPLACE FUNCTION public.handle_new_organization()
RETURNS TRIGGER AS $$
DECLARE
  new_pipeline_id uuid;
BEGIN
  -- 1. Create Default Pipeline
  INSERT INTO public.pipelines (organization_id, name)
  VALUES (NEW.id, 'Pipeline Principal')
  RETURNING id INTO new_pipeline_id;

  -- 2. Create 5 Default Stages
  INSERT INTO public.pipeline_stages (organization_id, pipeline_id, name, rank, target_volume)
  VALUES 
    (NEW.id, new_pipeline_id, 'Em atendimento', 10, 0),
    (NEW.id, new_pipeline_id, 'Follow-up', 20, 0),
    (NEW.id, new_pipeline_id, 'Reunião agendada', 30, 0),
    (NEW.id, new_pipeline_id, 'Em negociação', 40, 0),
    (NEW.id, new_pipeline_id, 'Venda ganha', 50, 0);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_organization_created
  AFTER INSERT ON public.organizations
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_organization();
