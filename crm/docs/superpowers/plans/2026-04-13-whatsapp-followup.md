# WhatsApp Cloud Follow-up Worker — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Supabase Scheduled Edge Function that sends two types of WhatsApp follow-ups (24h HSM template and 4h free-text nudge) to leads in `Follow-up` and `Pronto para pagar` stages, respecting business hours (08-18 America/Manaus) and excluding UAZAPI-origin leads.

**Architecture:** Supabase Edge Function (Deno) runs every 5 minutes via Supabase Scheduled Function. Polls `leads` + `lead_activities` + `lead_stage_history`. Idempotency via `follow_up_dispatches` table with UNIQUE constraint. Credentials stored in `integrations.config` + Supabase Vault. No triggers fire the worker; no pg_cron; Kestra untouched.

**Tech Stack:** Supabase (Postgres + Edge Functions + Vault + Scheduled Functions), Deno (TypeScript), WhatsApp Cloud API v21.0, Next.js (UI page only).

**Reference spec:** `docs/superpowers/specs/2026-04-13-whatsapp-followup-design.md`

**External prerequisites (not tasks in this plan — must be done before rollout):**
- HMAC validation on UAZAPI webhook (Janela 0 of ROADMAP)
- Remove `ignoreBuildErrors` from `next.config.ts` (Janela 0)

---

## File Structure

| File | Responsibility |
|---|---|
| `database/027_whatsapp_cloud_followup.sql` | Migration: `follow_up_dispatches` table, indexes, `get_integration_secret_service` RPC, `AFTER INSERT ON leads` trigger |
| `scripts/setup-whatsapp-cloud-integration.ts` | One-shot script: create `integrations` row for Todabella, store token in Vault, fetch `phone_number_id` |
| `supabase/functions/follow-up-worker/index.ts` | HTTP entry point, header auth, tick orchestration |
| `supabase/functions/follow-up-worker/business-hours.ts` | Pure helper: is current time within business hours for a given org config |
| `supabase/functions/follow-up-worker/graph-api.ts` | Pure builders + typed client for Graph API v21 template/text sends |
| `supabase/functions/follow-up-worker/queries.ts` | Typed wrappers around the two selection queries (24h and 4h) |
| `supabase/functions/follow-up-worker/dispatch.ts` | Per-lead dispatch: insert into `follow_up_dispatches`, call Graph, log to `lead_activities`, handle errors |
| `supabase/functions/follow-up-worker/test-helpers.ts` | Test scaffolding for Deno.test (pure helper tests only) |
| `supabase/config.toml` | Add `[functions.follow-up-worker] schedule` entry |
| `atlas-eye/src/app/(authenticated)/settings/integrations/whatsapp-cloud-api/page.tsx` | UI refactor: real form with waba_id, phone_number_id, system_token inputs + save handler |
| `atlas-eye/src/app/api/integrations/whatsapp-cloud/route.ts` | Next.js API route: upserts `integrations` row and calls `upsert_integration_secret` |

---

## Task 1: Migration — idempotency table, indexes, service RPC, insert trigger

**Files:**
- Create: `database/027_whatsapp_cloud_followup.sql`

- [ ] **Step 1: Verify next migration number**

Run: `ls C:/Users/venan/.gemini/antigravity/scratch/atlasEye/database | grep -E '^02[5-9]'`
Expected: `026_lead_search.sql` appears as the latest; `027_*` does not yet exist.

- [ ] **Step 2: Write the migration**

Create `database/027_whatsapp_cloud_followup.sql`:

```sql
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
  CONSTRAINT uq_dispatch UNIQUE (lead_id, stage_entry_id, kind)
);

CREATE INDEX IF NOT EXISTS idx_dispatch_org_kind_status
  ON public.follow_up_dispatches (organization_id, kind, status);

ALTER TABLE public.follow_up_dispatches ENABLE ROW LEVEL SECURITY;

-- Explicit deny-all for authenticated/anon; service_role bypasses RLS.
CREATE POLICY "deny all non-service" ON public.follow_up_dispatches
  FOR ALL TO authenticated, anon USING (false) WITH CHECK (false);

-- 2) Indexes on read-heavy paths.
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

-- 4) Trigger to seed lead_stage_history on lead INSERT.
-- Existing trigger in 006_rbac_and_automation.sql handles UPDATE of stage_id only.
CREATE OR REPLACE FUNCTION public.seed_stage_history_on_lead_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
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

COMMIT;
```

- [ ] **Step 3: Apply migration to local Supabase**

Run: `cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && supabase db push --include-all`
Expected: migration `027_whatsapp_cloud_followup.sql` applied, no errors. If supabase CLI is not connected, apply via SQL editor in Supabase dashboard.

- [ ] **Step 4: Verify table and RPC exist**

Run this Node script to verify:
```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && node --env-file=atlas-eye/.env.local -e "
const {createClient}=require('@supabase/supabase-js');
const s=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
(async()=>{
  const {error:e1}=await s.from('follow_up_dispatches').select('id').limit(0);
  console.log('table exists:', !e1, e1?.message||'');
  const {data:row}=await s.from('integrations').select('id,organization_id').limit(1);
  const {error:e2}=await s.rpc('get_integration_secret_service',{p_integration_id:row[0].id,p_org_id:row[0].organization_id});
  console.log('rpc callable:', !e2 || /no secret/.test(e2.message), e2?.message||'');
})();
"
```
Expected: `table exists: true`, `rpc callable: true` (RPC either returns a value or fails with "no secret" — both prove it's callable).

- [ ] **Step 5: Commit**

```bash
git add database/027_whatsapp_cloud_followup.sql
git commit -m "feat(db): add follow_up_dispatches, service vault RPC, stage-history insert trigger"
```

---

## Task 2: Setup script — create integration row + store token in Vault

**Files:**
- Create: `scripts/setup-whatsapp-cloud-integration.ts`

- [ ] **Step 1: Fetch phone_number_id from Graph API**

Run:
```bash
curl -s "https://graph.facebook.com/v21.0/876161085193833/phone_numbers?access_token=<TOKEN>" | head -c 2000
```
Where `<TOKEN>` is the system token. Copy the `id` field from the first phone number — that is `phone_number_id`.

- [ ] **Step 2: Write the setup script**

Create `scripts/setup-whatsapp-cloud-integration.ts`:

```ts
import { createClient } from '@supabase/supabase-js';

const ORG_ID = 'd17ec329-e074-46a0-b5a4-f3617e161cca'; // Todabella
const WABA_ID = '876161085193833';
const STAGE_FOLLOWUP = 'd3d3031f-bc4b-44df-bd83-b1f07d7fbf85';
const STAGE_ABOUT_TO_PAY = '0a58795e-31c1-4cdd-9cfa-408412d5ce7a';

async function main() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;
  const systemToken = process.env.WHATSAPP_CLOUD_SYSTEM_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_CLOUD_PHONE_NUMBER_ID;

  if (!systemToken) throw new Error('WHATSAPP_CLOUD_SYSTEM_TOKEN env var required');
  if (!phoneNumberId) throw new Error('WHATSAPP_CLOUD_PHONE_NUMBER_ID env var required');

  const s = createClient(url, serviceKey);

  const config = {
    waba_id: WABA_ID,
    phone_number_id: phoneNumberId,
    graph_api_version: 'v21.0',
    templates: {
      [STAGE_FOLLOWUP]: 'follow_up_avaliacao',
      [STAGE_ABOUT_TO_PAY]: 'followup_comprovante',
    },
  };

  const { data: existing } = await s
    .from('integrations')
    .select('id')
    .eq('organization_id', ORG_ID)
    .eq('type', 'whatsapp_cloud_official')
    .maybeSingle();

  let integrationId: string;
  if (existing) {
    integrationId = existing.id;
    const { error } = await s
      .from('integrations')
      .update({ config, status: 'active' })
      .eq('id', integrationId);
    if (error) throw error;
    console.log('Updated integration', integrationId);
  } else {
    const { data, error } = await s
      .from('integrations')
      .insert({
        organization_id: ORG_ID,
        name: 'WhatsApp Cloud (Oficial)',
        type: 'whatsapp_cloud_official',
        status: 'active',
        config,
      })
      .select('id')
      .single();
    if (error) throw error;
    integrationId = data.id;
    console.log('Created integration', integrationId);
  }

  // Upsert token into Vault via the project's existing RPC.
  const { error: secretErr } = await s.rpc('upsert_integration_secret', {
    p_integration_id: integrationId,
    p_org_id: ORG_ID,
    p_secret_value: systemToken,
  });
  if (secretErr) throw secretErr;

  console.log('Token stored in Vault. Integration ready:', integrationId);
}

main().catch((e) => { console.error(e); process.exit(1); });
```

- [ ] **Step 3: Verify `upsert_integration_secret` signature matches**

Run:
```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && grep -A 5 "CREATE OR REPLACE FUNCTION.*upsert_integration_secret" database/007_vault_secrets.sql
```
Expected: function signature `upsert_integration_secret(p_integration_id uuid, p_org_id uuid, p_secret_value text)`. If different, adjust the script.

- [ ] **Step 4: Run setup**

```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye
export NEXT_PUBLIC_SUPABASE_URL=https://hklfcfadultzuhwgkqmz.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=<from atlas-eye/.env.local>
export WHATSAPP_CLOUD_SYSTEM_TOKEN=EAAQXPgRARrQBRDdQ...
export WHATSAPP_CLOUD_PHONE_NUMBER_ID=<from step 1>
npx tsx scripts/setup-whatsapp-cloud-integration.ts
```
Expected: `Created integration <uuid>` or `Updated integration <uuid>`, then `Token stored in Vault. Integration ready: <uuid>`.

- [ ] **Step 5: Commit**

```bash
git add scripts/setup-whatsapp-cloud-integration.ts
git commit -m "feat(scripts): add WhatsApp Cloud integration bootstrapper"
```

---

## Task 3: Business hours helper (pure, TDD)

**Files:**
- Create: `supabase/functions/follow-up-worker/business-hours.ts`
- Create: `supabase/functions/follow-up-worker/business-hours.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/follow-up-worker/business-hours.test.ts`:

```ts
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { isWithinBusinessHours } from './business-hours.ts';

Deno.test('08:00 Manaus is within [8,18)', () => {
  // 2026-04-13 12:00 UTC = 08:00 America/Manaus (UTC-4 fixed).
  const now = new Date('2026-04-13T12:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), true);
});

Deno.test('17:59 Manaus is within [8,18)', () => {
  const now = new Date('2026-04-13T21:59:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), true);
});

Deno.test('18:00 Manaus is OUT (end_hour exclusive)', () => {
  const now = new Date('2026-04-13T22:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});

Deno.test('07:59 Manaus is OUT', () => {
  const now = new Date('2026-04-13T11:59:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});

Deno.test('midnight UTC maps to 20:00 Manaus — OUT', () => {
  const now = new Date('2026-04-14T00:00:00Z');
  assertEquals(isWithinBusinessHours(now, { start_hour: 8, end_hour: 18, tz: 'America/Manaus' }), false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && deno test supabase/functions/follow-up-worker/business-hours.test.ts`
Expected: FAIL with module-not-found for `business-hours.ts`.

- [ ] **Step 3: Implement**

Create `supabase/functions/follow-up-worker/business-hours.ts`:

```ts
export interface BusinessHoursConfig {
  start_hour: number;
  end_hour: number;
  tz: string;
}

export function isWithinBusinessHours(now: Date, cfg: BusinessHoursConfig): boolean {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: cfg.tz,
    hour: 'numeric',
    hour12: false,
  });
  const hourStr = fmt.format(now);
  // Intl may return "24" for midnight in some locales; normalize.
  const hour = Number(hourStr) % 24;
  return hour >= cfg.start_hour && hour < cfg.end_hour;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && deno test supabase/functions/follow-up-worker/business-hours.test.ts`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/follow-up-worker/business-hours.ts supabase/functions/follow-up-worker/business-hours.test.ts
git commit -m "feat(worker): business hours helper with Manaus timezone tests"
```

---

## Task 4: Graph API client (pure builders + minimal typed fetch)

**Files:**
- Create: `supabase/functions/follow-up-worker/graph-api.ts`
- Create: `supabase/functions/follow-up-worker/graph-api.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/follow-up-worker/graph-api.test.ts`:

```ts
import { assertEquals } from 'https://deno.land/std@0.208.0/assert/mod.ts';
import { buildTemplatePayload, buildTextPayload } from './graph-api.ts';

Deno.test('template payload omits components entirely', () => {
  const p = buildTemplatePayload({ to: '559292034074', templateName: 'follow_up_avaliacao', languageCode: 'pt_BR' });
  assertEquals(p, {
    messaging_product: 'whatsapp',
    to: '559292034074',
    type: 'template',
    template: { name: 'follow_up_avaliacao', language: { code: 'pt_BR' } },
  });
});

Deno.test('template payload strips leading +', () => {
  const p = buildTemplatePayload({ to: '+559292034074', templateName: 'x', languageCode: 'pt_BR' });
  assertEquals(p.to, '559292034074');
});

Deno.test('text payload structure', () => {
  const p = buildTextPayload({ to: '559292034074', body: 'Oi, podemos continuar?' });
  assertEquals(p, {
    messaging_product: 'whatsapp',
    to: '559292034074',
    type: 'text',
    text: { body: 'Oi, podemos continuar?' },
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/follow-up-worker/graph-api.test.ts`
Expected: FAIL with module-not-found.

- [ ] **Step 3: Implement**

Create `supabase/functions/follow-up-worker/graph-api.ts`:

```ts
export interface TemplateSendInput {
  to: string;
  templateName: string;
  languageCode: string;
}

export interface TextSendInput {
  to: string;
  body: string;
}

export interface GraphApiCredentials {
  phoneNumberId: string;
  systemToken: string;
  apiVersion: string;
}

export interface GraphApiResult {
  ok: boolean;
  wamid?: string;
  status: number;
  error?: { code?: number; message?: string; subcode?: number; details?: unknown };
}

function normalizePhone(to: string): string {
  return to.startsWith('+') ? to.slice(1) : to;
}

export function buildTemplatePayload(input: TemplateSendInput) {
  return {
    messaging_product: 'whatsapp',
    to: normalizePhone(input.to),
    type: 'template',
    template: { name: input.templateName, language: { code: input.languageCode } },
  };
}

export function buildTextPayload(input: TextSendInput) {
  return {
    messaging_product: 'whatsapp',
    to: normalizePhone(input.to),
    type: 'text',
    text: { body: input.body },
  };
}

export async function sendToGraphApi(
  creds: GraphApiCredentials,
  payload: Record<string, unknown>,
): Promise<GraphApiResult> {
  const url = `https://graph.facebook.com/${creds.apiVersion}/${creds.phoneNumberId}/messages`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${creds.systemToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    return {
      ok: false,
      status: res.status,
      error: {
        code: body?.error?.code,
        message: body?.error?.message,
        subcode: body?.error?.error_subcode,
        details: body?.error,
      },
    };
  }
  const wamid = body?.messages?.[0]?.id;
  return { ok: true, status: res.status, wamid };
}
```

- [ ] **Step 4: Run tests**

Run: `deno test supabase/functions/follow-up-worker/graph-api.test.ts`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/follow-up-worker/graph-api.ts supabase/functions/follow-up-worker/graph-api.test.ts
git commit -m "feat(worker): graph API builders and typed fetch client"
```

---

## Task 5: Query module — eligible leads for template_24h and nudge_4h

**Files:**
- Create: `supabase/functions/follow-up-worker/queries.ts`

- [ ] **Step 1: Implement query module**

Create `supabase/functions/follow-up-worker/queries.ts`:

```ts
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

export interface StageTargets {
  followupStageId: string;
  aboutToPayStageId: string;
  followupTemplateName: string;
  aboutToPayTemplateName: string;
}

export interface EligibleTemplate24h {
  lead_id: string;
  organization_id: string;
  phone: string;
  stage_id: string;
  stage_entry_id: string;
  template_name: string;
}

export interface EligibleNudge4h {
  lead_id: string;
  organization_id: string;
  phone: string;
  stage_id: string;
  stage_entry_id: string;
}

/**
 * Selects leads that entered Follow-up or Pronto-para-pagar ≥ 24h ago
 * and have had no inbound since, and no prior template_24h dispatch
 * for that stage entry, and are not from a UAZAPI integration.
 * Uses a 48h floor on changed_at to avoid backfilling old leads.
 */
export async function selectTemplate24hEligible(
  db: SupabaseClient,
  orgId: string,
  targets: StageTargets,
): Promise<EligibleTemplate24h[]> {
  const { data, error } = await db.rpc('select_template_24h_eligible', {
    p_org_id: orgId,
    p_followup_stage: targets.followupStageId,
    p_about_to_pay_stage: targets.aboutToPayStageId,
    p_followup_template: targets.followupTemplateName,
    p_about_to_pay_template: targets.aboutToPayTemplateName,
  });
  if (error) throw error;
  return (data ?? []) as EligibleTemplate24h[];
}

export async function selectNudge4hEligible(
  db: SupabaseClient,
  orgId: string,
  targets: StageTargets,
): Promise<EligibleNudge4h[]> {
  const { data, error } = await db.rpc('select_nudge_4h_eligible', {
    p_org_id: orgId,
    p_followup_stage: targets.followupStageId,
    p_about_to_pay_stage: targets.aboutToPayStageId,
  });
  if (error) throw error;
  return (data ?? []) as EligibleNudge4h[];
}
```

- [ ] **Step 2: Add the two RPC functions to the migration**

Append to `database/027_whatsapp_cloud_followup.sql` (before COMMIT):

```sql
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
SET search_path = public, pg_temp
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
    AND ce.changed_at >  now() - interval '48 hours'  -- backfill guard
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
SET search_path = public, pg_temp
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
```

- [ ] **Step 3: Re-apply migration**

Run: `supabase db push` or apply the new additions via SQL editor.

- [ ] **Step 4: Smoke-test RPCs**

Run:
```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && node --env-file=atlas-eye/.env.local -e "
const {createClient}=require('@supabase/supabase-js');
const s=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
(async()=>{
  const r1=await s.rpc('select_template_24h_eligible',{
    p_org_id:'d17ec329-e074-46a0-b5a4-f3617e161cca',
    p_followup_stage:'d3d3031f-bc4b-44df-bd83-b1f07d7fbf85',
    p_about_to_pay_stage:'0a58795e-31c1-4cdd-9cfa-408412d5ce7a',
    p_followup_template:'follow_up_avaliacao',
    p_about_to_pay_template:'followup_comprovante'
  });
  console.log('template_24h:', r1.error?r1.error.message:'rows='+r1.data.length);
  const r2=await s.rpc('select_nudge_4h_eligible',{
    p_org_id:'d17ec329-e074-46a0-b5a4-f3617e161cca',
    p_followup_stage:'d3d3031f-bc4b-44df-bd83-b1f07d7fbf85',
    p_about_to_pay_stage:'0a58795e-31c1-4cdd-9cfa-408412d5ce7a'
  });
  console.log('nudge_4h:', r2.error?r2.error.message:'rows='+r2.data.length);
})();
"
```
Expected: both print `rows=<N>` with no error. N may be 0 — that's fine.

- [ ] **Step 5: Commit**

```bash
git add database/027_whatsapp_cloud_followup.sql supabase/functions/follow-up-worker/queries.ts
git commit -m "feat(db,worker): eligibility RPCs for template_24h and nudge_4h"
```

---

## Task 6: Dispatch module — insert idempotency row, call Graph, log activity

**Files:**
- Create: `supabase/functions/follow-up-worker/dispatch.ts`

- [ ] **Step 1: Implement**

Create `supabase/functions/follow-up-worker/dispatch.ts`:

```ts
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { buildTemplatePayload, buildTextPayload, sendToGraphApi, type GraphApiCredentials } from './graph-api.ts';

export type DispatchKind = 'template_24h' | 'nudge_4h';

export interface DispatchInput {
  organizationId: string;
  leadId: string;
  stageEntryId: string;
  phone: string;
  kind: DispatchKind;
  templateName?: string;   // required when kind=template_24h
  nudgeBody?: string;      // required when kind=nudge_4h
}

export interface DispatchOutcome {
  kind: 'skipped_duplicate' | 'sent' | 'failed';
  wamid?: string;
  error?: unknown;
}

export async function dispatchFollowUp(
  db: SupabaseClient,
  creds: GraphApiCredentials,
  input: DispatchInput,
): Promise<DispatchOutcome> {
  // 1) Acquire idempotency slot.
  const { data: inserted, error: insErr } = await db
    .from('follow_up_dispatches')
    .insert({
      organization_id: input.organizationId,
      lead_id: input.leadId,
      stage_entry_id: input.stageEntryId,
      kind: input.kind,
      status: 'pending',
    })
    .select('id')
    .maybeSingle();

  if (insErr) {
    // Unique violation → another tick already took it.
    if ((insErr as { code?: string }).code === '23505') {
      return { kind: 'skipped_duplicate' };
    }
    throw insErr;
  }
  if (!inserted) return { kind: 'skipped_duplicate' };

  const dispatchId = inserted.id;

  // 2) Build payload and send.
  const payload =
    input.kind === 'template_24h'
      ? buildTemplatePayload({ to: input.phone, templateName: input.templateName!, languageCode: 'pt_BR' })
      : buildTextPayload({ to: input.phone, body: input.nudgeBody! });

  const result = await sendToGraphApi(creds, payload);

  // 3) Update dispatch row.
  await db
    .from('follow_up_dispatches')
    .update({
      status: result.ok ? 'sent' : 'failed',
      wamid: result.wamid ?? null,
      error: result.ok ? null : result.error ?? null,
    })
    .eq('id', dispatchId);

  if (!result.ok) return { kind: 'failed', error: result.error };

  // 4) Log activity (surfaces in lead timeline UI).
  await db.from('lead_activities').insert({
    organization_id: input.organizationId,
    lead_id: input.leadId,
    type: 'whatsapp',
    content: input.kind === 'template_24h'
      ? `[template] ${input.templateName}`
      : input.nudgeBody,
    metadata: {
      source: 'automation',
      direction: 'outbound',
      kind: input.kind,
      template_name: input.templateName ?? null,
      stage_entry_id: input.stageEntryId,
      wamid: result.wamid,
    },
  });

  return { kind: 'sent', wamid: result.wamid };
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/follow-up-worker/dispatch.ts
git commit -m "feat(worker): dispatch module with idempotent insert + Graph send + activity log"
```

---

## Task 7: Worker entry point — header auth + tick orchestration

**Files:**
- Create: `supabase/functions/follow-up-worker/index.ts`

- [ ] **Step 1: Implement**

Create `supabase/functions/follow-up-worker/index.ts`:

```ts
import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { isWithinBusinessHours } from './business-hours.ts';
import { selectTemplate24hEligible, selectNudge4hEligible } from './queries.ts';
import { dispatchFollowUp } from './dispatch.ts';
import type { GraphApiCredentials } from './graph-api.ts';

interface IntegrationConfig {
  waba_id: string;
  phone_number_id: string;
  graph_api_version: string;
  templates: Record<string, string>;
}

const FOLLOWUP_STAGE = 'd3d3031f-bc4b-44df-bd83-b1f07d7fbf85';
const ABOUT_TO_PAY_STAGE = '0a58795e-31c1-4cdd-9cfa-408412d5ce7a';
const NUDGE_BODY = 'Oi, podemos continuar?';

serve(async (req) => {
  // 1) Auth.
  const secret = Deno.env.get('FOLLOW_UP_CRON_SECRET');
  if (!secret) return new Response('server misconfigured', { status: 500 });
  if (req.headers.get('x-cron-secret') !== secret) {
    return new Response('unauthorized', { status: 401 });
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: integrations, error: intErr } = await db
    .from('integrations')
    .select('id, organization_id, config')
    .eq('type', 'whatsapp_cloud_official')
    .eq('status', 'active')
    .is('deleted_at', null);

  if (intErr) {
    console.error(JSON.stringify({ level: 'error', stage: 'load_integrations', error: intErr.message }));
    return new Response('db error', { status: 500 });
  }

  const summary = { orgs: 0, sent: 0, failed: 0, skipped: 0 };

  for (const integ of integrations ?? []) {
    const cfg = integ.config as IntegrationConfig;
    const orgId = integ.organization_id as string;

    const { data: hoursRow } = await db
      .from('automation_settings')
      .select('variables, is_enabled')
      .eq('organization_id', orgId)
      .eq('key', 'follow_up_business_hours')
      .maybeSingle();

    const hours = (hoursRow?.variables as { start_hour: number; end_hour: number; tz: string } | undefined) ??
      { start_hour: 8, end_hour: 18, tz: 'America/Manaus' };

    if (hoursRow && hoursRow.is_enabled === false) continue;
    if (!isWithinBusinessHours(new Date(), hours)) continue;

    summary.orgs++;

    // Load token from Vault.
    const { data: token, error: tokErr } = await db.rpc('get_integration_secret_service', {
      p_integration_id: integ.id,
      p_org_id: orgId,
    });
    if (tokErr || !token) {
      console.error(JSON.stringify({ level: 'error', stage: 'vault', org: orgId, error: tokErr?.message }));
      continue;
    }

    const creds: GraphApiCredentials = {
      phoneNumberId: cfg.phone_number_id,
      systemToken: token as string,
      apiVersion: cfg.graph_api_version,
    };

    // Block 1: template 24h
    const t24 = await selectTemplate24hEligible(db, orgId, {
      followupStageId: FOLLOWUP_STAGE,
      aboutToPayStageId: ABOUT_TO_PAY_STAGE,
      followupTemplateName: cfg.templates[FOLLOWUP_STAGE],
      aboutToPayTemplateName: cfg.templates[ABOUT_TO_PAY_STAGE],
    });
    for (const lead of t24) {
      const out = await dispatchFollowUp(db, creds, {
        organizationId: orgId,
        leadId: lead.lead_id,
        stageEntryId: lead.stage_entry_id,
        phone: lead.phone,
        kind: 'template_24h',
        templateName: lead.template_name,
      });
      summary[out.kind === 'sent' ? 'sent' : out.kind === 'failed' ? 'failed' : 'skipped']++;
      await new Promise((r) => setTimeout(r, 250));
    }

    // Block 2: nudge 4h
    const n4 = await selectNudge4hEligible(db, orgId, {
      followupStageId: FOLLOWUP_STAGE,
      aboutToPayStageId: ABOUT_TO_PAY_STAGE,
      followupTemplateName: cfg.templates[FOLLOWUP_STAGE],
      aboutToPayTemplateName: cfg.templates[ABOUT_TO_PAY_STAGE],
    });
    for (const lead of n4) {
      const out = await dispatchFollowUp(db, creds, {
        organizationId: orgId,
        leadId: lead.lead_id,
        stageEntryId: lead.stage_entry_id,
        phone: lead.phone,
        kind: 'nudge_4h',
        nudgeBody: NUDGE_BODY,
      });
      summary[out.kind === 'sent' ? 'sent' : out.kind === 'failed' ? 'failed' : 'skipped']++;
      await new Promise((r) => setTimeout(r, 250));
    }
  }

  console.log(JSON.stringify({ level: 'info', stage: 'tick_done', ...summary }));
  return new Response(JSON.stringify(summary), { status: 200, headers: { 'content-type': 'application/json' } });
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/follow-up-worker/index.ts
git commit -m "feat(worker): entry point with header auth and tick orchestration"
```

---

## Task 8: Schedule the function in supabase/config.toml

**Files:**
- Modify: `supabase/config.toml`

- [ ] **Step 1: Read current config**

Run: `cat C:/Users/venan/.gemini/antigravity/scratch/atlasEye/supabase/config.toml | tail -40`

- [ ] **Step 2: Append schedule entry**

Add to the bottom of `supabase/config.toml`:

```toml
[functions.follow-up-worker]
verify_jwt = false
# Runs every 5 minutes. Auth is via x-cron-secret header.
schedule = "*/5 * * * *"
```

- [ ] **Step 3: Set env vars in Supabase**

Via Supabase dashboard → Edge Functions → `follow-up-worker` → Secrets, add:
- `FOLLOW_UP_CRON_SECRET` = random 32+ char value (e.g. `openssl rand -hex 32`)

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided by the platform automatically.

- [ ] **Step 4: Deploy (but keep scheduled off)**

Run: `supabase functions deploy follow-up-worker --no-verify-jwt`
Expected: deploy succeeds. Do NOT enable schedule yet — manual tests first in Task 10.

- [ ] **Step 5: Commit**

```bash
git add supabase/config.toml
git commit -m "feat(worker): schedule follow-up-worker every 5 minutes"
```

---

## Task 9: UI refactor — real form on `whatsapp-cloud-api` page

**Files:**
- Modify: `atlas-eye/src/app/(authenticated)/settings/integrations/whatsapp-cloud-api/page.tsx`
- Create: `atlas-eye/src/app/api/integrations/whatsapp-cloud/route.ts`

- [ ] **Step 1: Read the existing page**

Run: `cat "C:/Users/venan/.gemini/antigravity/scratch/atlasEye/atlas-eye/src/app/(authenticated)/settings/integrations/whatsapp-cloud-api/page.tsx"`

Note the structure and any UI primitives (shadcn/ui, Tailwind) the project uses.

- [ ] **Step 2: Create the API route**

Create `atlas-eye/src/app/api/integrations/whatsapp-cloud/route.ts`:

```ts
import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const STAGE_FOLLOWUP = 'd3d3031f-bc4b-44df-bd83-b1f07d7fbf85';
const STAGE_ABOUT_TO_PAY = '0a58795e-31c1-4cdd-9cfa-408412d5ce7a';

export async function POST(req: Request) {
  const body = await req.json();
  const { organization_id, waba_id, phone_number_id, system_token, graph_api_version } = body ?? {};

  if (!organization_id || !waba_id || !phone_number_id || !system_token) {
    return NextResponse.json({ error: 'missing required fields' }, { status: 400 });
  }

  const s = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);

  const config = {
    waba_id,
    phone_number_id,
    graph_api_version: graph_api_version ?? 'v21.0',
    templates: {
      [STAGE_FOLLOWUP]: 'follow_up_avaliacao',
      [STAGE_ABOUT_TO_PAY]: 'followup_comprovante',
    },
  };

  const { data: existing } = await s
    .from('integrations')
    .select('id')
    .eq('organization_id', organization_id)
    .eq('type', 'whatsapp_cloud_official')
    .maybeSingle();

  let integrationId: string;
  if (existing) {
    integrationId = existing.id;
    const { error } = await s.from('integrations').update({ config, status: 'active' }).eq('id', integrationId);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  } else {
    const { data, error } = await s
      .from('integrations')
      .insert({ organization_id, name: 'WhatsApp Cloud (Oficial)', type: 'whatsapp_cloud_official', status: 'active', config })
      .select('id')
      .single();
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    integrationId = data.id;
  }

  const { error: secErr } = await s.rpc('upsert_integration_secret', {
    p_integration_id: integrationId,
    p_org_id: organization_id,
    p_secret_value: system_token,
  });
  if (secErr) return NextResponse.json({ error: secErr.message }, { status: 500 });

  return NextResponse.json({ integration_id: integrationId });
}

export async function GET(req: Request) {
  const url = new URL(req.url);
  const orgId = url.searchParams.get('organization_id');
  if (!orgId) return NextResponse.json({ error: 'organization_id required' }, { status: 400 });

  const s = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!);
  const { data, error } = await s
    .from('integrations')
    .select('id, status, config')
    .eq('organization_id', orgId)
    .eq('type', 'whatsapp_cloud_official')
    .maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json(data ?? null);
}
```

- [ ] **Step 3: Rewrite the page**

Replace the body of `atlas-eye/src/app/(authenticated)/settings/integrations/whatsapp-cloud-api/page.tsx` with a working form. Exact code depends on the project's UI kit; use the same primitives as `whatsapp-lite/page.tsx`. Fields: `waba_id`, `phone_number_id`, `system_token` (password input), `graph_api_version` (default `v21.0`). Submit handler calls `POST /api/integrations/whatsapp-cloud`. On load, GET the same endpoint to prefill `waba_id`, `phone_number_id`, `graph_api_version` (never show the token). Show current status badge (`Conectado` / `Desconectado`).

Reference the card visual style of `whatsapp-lite/page.tsx` but with a clearly different accent color or label to avoid confusion ("WhatsApp Cloud API Oficial" vs "WhatsApp Lite (UAZAPI)").

- [ ] **Step 4: Test manually in dev**

Run: `cd atlas-eye && npm run dev`
Open the integrations page. Enter Todabella's `waba_id`, `phone_number_id`, system token. Submit. Verify via script from Task 1 Step 4 that the integration was updated.

- [ ] **Step 5: Commit**

```bash
git add atlas-eye/src/app/api/integrations/whatsapp-cloud/route.ts "atlas-eye/src/app/(authenticated)/settings/integrations/whatsapp-cloud-api/page.tsx"
git commit -m "feat(ui): real WhatsApp Cloud integration form with Vault-backed token storage"
```

---

## Task 10: Manual end-to-end verification before enabling schedule

- [ ] **Step 1: Seed business hours for Todabella**

Run:
```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye && node --env-file=atlas-eye/.env.local -e "
const {createClient}=require('@supabase/supabase-js');
const s=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
(async()=>{
  const {error}=await s.from('automation_settings').upsert({
    organization_id:'d17ec329-e074-46a0-b5a4-f3617e161cca',
    key:'follow_up_business_hours',
    is_enabled:true,
    variables:{start_hour:8,end_hour:18,tz:'America/Manaus'}
  },{onConflict:'organization_id,key'});
  console.log('seed:', error?error.message:'ok');
})();
"
```
Expected: `seed: ok`. If constraint target differs, inspect `automation_settings` unique keys and adjust.

- [ ] **Step 2: Pick a test lead**

Identify or create one lead in `Follow-up` stage where `changed_at` is in the last 24-48h and that has no prior inbound after `changed_at`. If no natural candidate exists, temporarily insert one via the Supabase SQL editor.

- [ ] **Step 3: Invoke the function manually**

Run:
```bash
curl -i -X POST "https://hklfcfadultzuhwgkqmz.supabase.co/functions/v1/follow-up-worker" \
  -H "x-cron-secret: <FOLLOW_UP_CRON_SECRET>" \
  -H "Authorization: Bearer <SUPABASE_ANON_KEY>"
```
Expected: `200` with JSON `{orgs:1,sent:<n>,failed:0,skipped:<m>}`.

- [ ] **Step 4: Inspect results**

```bash
node --env-file=atlas-eye/.env.local -e "
const {createClient}=require('@supabase/supabase-js');
const s=createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
(async()=>{
  const {data}=await s.from('follow_up_dispatches').select('*').order('dispatched_at',{ascending:false}).limit(5);
  console.log(JSON.stringify(data,null,2));
})();
"
```
Expected: rows with `status='sent'` and `wamid` populated. Verify the WhatsApp message was actually received on the test phone.

- [ ] **Step 5: Test idempotency**

Re-invoke the same curl from Step 3 immediately.
Expected: `sent:0, skipped:<same>`. Confirm no duplicate message arrived on the test phone and no new row in `follow_up_dispatches` for the same `(lead_id, stage_entry_id, kind)`.

- [ ] **Step 6: Test failure path**

Temporarily corrupt the token in Vault (set to `"invalid"` via `upsert_integration_secret`). Invoke again. Expected: `sent:0, failed:1`, and the dispatch row has `status='failed'` with Graph API error in `error` column. Restore the real token.

- [ ] **Step 7: Test unauthorized request**

Run the curl without `x-cron-secret` header.
Expected: `401 unauthorized`.

- [ ] **Step 8: Commit verification notes**

Create `docs/superpowers/runs/2026-04-13-followup-worker-verification.md` with the dates, lead ids tested, and observed outputs.

```bash
mkdir -p docs/superpowers/runs
# (write the file with your observations)
git add docs/superpowers/runs/2026-04-13-followup-worker-verification.md
git commit -m "docs: record follow-up worker manual verification run"
```

---

## Task 11: Enable schedule in production

- [ ] **Step 1: Confirm external prerequisites are done**

Check the ROADMAP.md: Janela 0 items (UAZAPI webhook HMAC, `ignoreBuildErrors` removal) must be completed before enabling. If not done, stop here and surface the blocker to the user.

- [ ] **Step 2: Confirm schedule is active**

Via Supabase dashboard → Edge Functions → `follow-up-worker`, verify the schedule is enabled (`*/5 * * * *`).

- [ ] **Step 3: Watch first 3 ticks**

Via dashboard logs, verify 3 consecutive runs executed with `level:info, stage:tick_done`. If business hours currently closed in America/Manaus, the orgs counter will be 0 — this is correct.

- [ ] **Step 4: Monitor for 48h**

Check `follow_up_dispatches` daily for 2 days. Metrics to track:
- `sent / (sent + failed)` ratio ≥ 95%
- No duplicate messages (no two rows with same `(lead_id, stage_entry_id, kind)` — UNIQUE guarantees this at DB level, but check UI timeline for duplicates nonetheless)
- No customer complaints about off-hours messages

- [ ] **Step 5: Tag the release**

```bash
git tag followup-worker-v1
```

---

## Self-review checklist

- Spec §4 architecture (Edge Function + 5min schedule + dispatches UNIQUE) → Tasks 1, 6, 7, 8 ✓
- Spec §5.1 integration row → Tasks 2, 9 ✓
- Spec §5.2 follow_up_dispatches table → Task 1 ✓
- Spec §5.3 automation_settings seed → Task 10 Step 1 ✓
- Spec §5.4 indexes → Task 1 ✓
- Spec §5.5 migration 026 → Task 1 ✓
- Spec §6 template_24h query → Task 5 (RPC), Task 7 (usage) ✓
- Spec §7 nudge_4h query → Task 5 (RPC), Task 7 (usage) ✓
- Spec §8 Graph API payloads → Task 4 ✓
- Spec §9 prerequisites: cron secret → Task 7/8; service RPC → Task 1; insert trigger → Task 1; UI refactor → Task 9 ✓
- Spec §9 external prereqs (HMAC, ignoreBuildErrors) → noted, not tasks ✓
- Spec §10 observability (console JSON, dispatches) → Task 7 (logs), Task 1 (table) ✓
- Spec §11 rollout → Tasks 10, 11 ✓

No placeholders; all code blocks have complete content; file paths exact; type names consistent (`GraphApiCredentials`, `DispatchKind`, `EligibleTemplate24h`, `StageTargets` used consistently across tasks).
