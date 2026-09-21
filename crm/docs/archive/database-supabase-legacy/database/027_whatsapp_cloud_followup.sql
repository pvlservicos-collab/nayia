-- 027_whatsapp_cloud_followup.sql
-- Feature: WhatsApp Cloud follow-up worker.
-- Creates: follow_up_dispatches table, supporting indexes,
--          get_integration_secret_service RPC (service_role only),
--          AFTER INSERT ON leads trigger for lead_stage_history seed.

BEGIN;

-- 1) follow_up_dispatches: authoritative idempotency log for the worker.
CREATE TABLE IF NOT EXISTS public.follow_up_dispatches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  lead_id uuid NOT NULL,
  stage_entry_id uuid NOT NULL REFERENCES public.lead_stage_history(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('template_24h','nudge_4h')),
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  wamid text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')),
  error jsonb,
  attempt int NOT NULL DEFAULT 1,
  CONSTRAINT uq_dispatch UNIQUE (lead_id, stage_entry_id, kind),
  CONSTRAINT fk_dispatch_lead FOREIGN KEY (organization_id, lead_id)
    REFERENCES public.leads(organization_id, id) ON DELETE CASCADE
);

-- Idempotent guard: ensure the composite FK exists in environments where the
-- table was created by an earlier version of this migration (CREATE TABLE
-- IF NOT EXISTS does not re-run, so we must add the constraint separately).
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_dispatch_lead'
      AND conrelid = 'public.follow_up_dispatches'::regclass
  ) THEN
    ALTER TABLE public.follow_up_dispatches
      ADD CONSTRAINT fk_dispatch_lead
      FOREIGN KEY (organization_id, lead_id)
      REFERENCES public.leads(organization_id, id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_dispatch_org_kind_status
  ON public.follow_up_dispatches (organization_id, kind, status);

ALTER TABLE public.follow_up_dispatches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny all non-service" ON public.follow_up_dispatches;
CREATE POLICY "deny all non-service" ON public.follow_up_dispatches
  FOR ALL TO authenticated, anon USING (false) WITH CHECK (false);

-- 2) Supporting indexes on read paths.
CREATE INDEX IF NOT EXISTS idx_activities_inbound_by_lead
  ON public.lead_activities (lead_id, created_at DESC)
  WHERE metadata->>'direction' = 'inbound';

CREATE INDEX IF NOT EXISTS idx_stage_history_lead_stage
  ON public.lead_stage_history (lead_id, to_stage_id, changed_at DESC);

-- 3) Service-role RPC to read Vault secrets without going through has_permission().
CREATE OR REPLACE FUNCTION public.get_integration_secret_service(
  p_integration_id uuid,
  p_org_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, vault, pg_temp
AS $$
DECLARE
  v_secret_id uuid;
  v_decrypted text;
BEGIN
  SELECT secret_id INTO v_secret_id
  FROM public.integrations
  WHERE id = p_integration_id AND organization_id = p_org_id;

  IF v_secret_id IS NULL THEN
    RAISE EXCEPTION 'integration not found or has no secret (integration_id=%, org_id=%)',
      p_integration_id, p_org_id;
  END IF;

  SELECT decrypted_secret INTO v_decrypted
  FROM vault.decrypted_secrets
  WHERE id = v_secret_id;

  RETURN v_decrypted;
END;
$$;

REVOKE ALL ON FUNCTION public.get_integration_secret_service(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_integration_secret_service(uuid, uuid) FROM authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_integration_secret_service(uuid, uuid) TO service_role;

-- 4) Seed lead_stage_history on lead INSERT (existing trigger only handles UPDATE).
CREATE OR REPLACE FUNCTION public.seed_stage_history_on_lead_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.stage_id IS NOT NULL THEN
    INSERT INTO public.lead_stage_history
      (organization_id, lead_id, from_stage_id, to_stage_id, changed_by_member_id, changed_at)
    VALUES
      (NEW.organization_id, NEW.id, NULL, NEW.stage_id, NULL, NEW.created_at);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_lead_insert_seed_stage_history ON public.leads;
CREATE TRIGGER on_lead_insert_seed_stage_history
  AFTER INSERT ON public.leads
  FOR EACH ROW EXECUTE PROCEDURE public.seed_stage_history_on_lead_insert();

-- 5) Eligibility RPCs (service_role only).

CREATE OR REPLACE FUNCTION public.select_template_24h_eligible(
  p_org_id uuid,
  p_followup_stage uuid,
  p_about_to_pay_stage uuid,
  p_followup_template text,
  p_about_to_pay_template text
) RETURNS TABLE (
  lead_id uuid,
  organization_id uuid,
  phone text,
  stage_id uuid,
  stage_entry_id uuid,
  template_name text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH current_entry AS (
    SELECT DISTINCT ON (l.id)
      l.id AS lead_id,
      l.organization_id,
      l.phone,
      l.stage_id,
      h.id AS stage_entry_id,
      h.changed_at
    FROM public.leads l
    LEFT JOIN public.integrations i ON i.id = l.integration_id
    JOIN public.lead_stage_history h
      ON h.lead_id = l.id AND h.to_stage_id = l.stage_id
    WHERE l.organization_id = p_org_id
      AND l.deleted_at IS NULL
      AND l.stage_id IN (p_followup_stage, p_about_to_pay_stage)
      AND (i.id IS NULL OR i.type <> 'whatsapp_lite')
    ORDER BY l.id, h.changed_at DESC
  )
  SELECT
    ce.lead_id,
    ce.organization_id,
    ce.phone,
    ce.stage_id,
    ce.stage_entry_id,
    CASE ce.stage_id
      WHEN p_followup_stage THEN p_followup_template
      WHEN p_about_to_pay_stage THEN p_about_to_pay_template
    END AS template_name
  FROM current_entry ce
  WHERE ce.changed_at <= now() - interval '24 hours'
    AND ce.changed_at >  now() - interval '48 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.lead_activities a
      WHERE a.lead_id = ce.lead_id
        AND a.metadata->>'direction' = 'inbound'
        AND a.created_at > ce.changed_at
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.follow_up_dispatches d
      WHERE d.lead_id = ce.lead_id
        AND d.stage_entry_id = ce.stage_entry_id
        AND d.kind = 'template_24h'
    );
$$;

REVOKE ALL ON FUNCTION public.select_template_24h_eligible(uuid,uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_template_24h_eligible(uuid,uuid,uuid,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.select_nudge_4h_eligible(
  p_org_id uuid,
  p_followup_stage uuid,
  p_about_to_pay_stage uuid
) RETURNS TABLE (
  lead_id uuid,
  organization_id uuid,
  phone text,
  stage_id uuid,
  stage_entry_id uuid
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH base AS (
    SELECT
      l.id AS lead_id, l.organization_id, l.phone, l.stage_id,
      (SELECT MAX(a.created_at) FROM public.lead_activities a
        WHERE a.lead_id = l.id AND a.metadata->>'direction'='outbound'
          AND COALESCE(a.metadata->>'kind','') <> 'nudge_4h') AS last_out,
      (SELECT MAX(a.created_at) FROM public.lead_activities a
        WHERE a.lead_id = l.id AND a.metadata->>'direction'='inbound') AS last_in,
      h.id AS stage_entry_id
    FROM public.leads l
    LEFT JOIN public.integrations i ON i.id = l.integration_id
    JOIN LATERAL (
      SELECT id FROM public.lead_stage_history
      WHERE lead_id = l.id AND to_stage_id = l.stage_id
      ORDER BY changed_at DESC LIMIT 1
    ) h ON true
    WHERE l.organization_id = p_org_id
      AND l.deleted_at IS NULL
      AND l.stage_id IN (p_followup_stage, p_about_to_pay_stage)
      AND (i.id IS NULL OR i.type <> 'whatsapp_lite')
  )
  SELECT lead_id, organization_id, phone, stage_id, stage_entry_id
  FROM base
  WHERE last_out IS NOT NULL
    AND last_out <= now() - interval '4 hours'
    AND (last_in IS NULL OR last_in < last_out)
    AND last_in IS NOT NULL
    AND last_in > now() - interval '24 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.follow_up_dispatches d
      WHERE d.lead_id = base.lead_id
        AND d.kind = 'nudge_4h'
        AND d.dispatched_at > COALESCE(base.last_in, '-infinity'::timestamptz)
    );
$$;

REVOKE ALL ON FUNCTION public.select_nudge_4h_eligible(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_nudge_4h_eligible(uuid,uuid,uuid) TO service_role;

-- 6) Service-role upsert for Vault secret (bypasses has_permission for internal callers).
--    Intended for: setup scripts, Edge Functions, API routes that already enforced
--    caller authorization upstream. Signature mirrors upsert_integration_secret.
CREATE OR REPLACE FUNCTION public.upsert_integration_secret_service(
    p_integration_id uuid,
    p_org_id         uuid,
    p_secret         jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_secret_id   uuid;
    v_secret_name text;
BEGIN
    SELECT secret_id INTO v_secret_id
    FROM public.integrations
    WHERE id              = p_integration_id
      AND organization_id = p_org_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Integration not found or does not belong to organization';
    END IF;

    v_secret_name := 'integration:' || p_integration_id::text;

    IF v_secret_id IS NULL THEN
        v_secret_id := vault.create_secret(
            p_secret::text,
            v_secret_name,
            'Integration credentials – org ' || p_org_id::text
        );

        UPDATE public.integrations
        SET secret_id  = v_secret_id,
            updated_at = now()
        WHERE id              = p_integration_id
          AND organization_id = p_org_id;
    ELSE
        PERFORM vault.update_secret(
            v_secret_id,
            p_secret::text,
            v_secret_name
        );
    END IF;

    RETURN v_secret_id;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_integration_secret_service(uuid, uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_integration_secret_service(uuid, uuid, jsonb) FROM authenticated, anon;
GRANT EXECUTE ON FUNCTION public.upsert_integration_secret_service(uuid, uuid, jsonb) TO service_role;

COMMIT;
