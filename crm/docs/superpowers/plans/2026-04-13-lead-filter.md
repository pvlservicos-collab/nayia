# Lead Filter Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the title-only Chat sidebar lead filter with a hybrid client/server search that covers name, phone, email, and WhatsApp/email message content — without busting the 1000-row Supabase default cap and without breaking existing permissions.

**Architecture:** Client filters the in-memory `LeadsContext.leads` while `q.length < 3`. For `q.length >= 3`, a new Next.js route `POST /api/leads/search` calls a new Postgres RPC `public.search_leads`, which UNIONs contact hits (title/email/phone-digits) with message hits (`lead_activities.content` where `type IN ('whatsapp','email')`). Partial GIN trigram indexes plus `unaccent` keep queries cheap and accent-insensitive. Pinned stay on top; contact matches rank above message matches.

**Tech Stack:** PostgreSQL 15 (via Supabase), `pg_trgm` + `unaccent` extensions, Next.js 15 (App Router) with TypeScript, `@supabase/ssr`, React 19. Project has no test framework — verification uses a psql-based SQL test script (following the existing `scripts/test-*.ts` convention) plus a manual browser QA checklist.

**Spec:** `docs/superpowers/specs/2026-04-13-lead-filter-design.md` — keep it open while implementing.

**Root-cause confirmation:** `supabase/config.toml` sets `max_rows = 1000` — that is why "Alcineia" is not found on orgs with >1000 leads. The server path bypasses that cap by filtering in-database before returning.

---

## File structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `database/026_lead_search.sql` | Extension, immutable helpers, partial GIN trigram indexes, `search_leads` RPC |
| Create | `scripts/test-search-leads.ts` | SQL smoke test — accent/phone/message/permission cases |
| Create | `atlas-eye/src/app/api/leads/search/route.ts` | Auth gate, org lookup, permissions, RPC call, reshape response |
| Create | `atlas-eye/src/hooks/useLeadSearch.ts` | Threshold + debounce + AbortController + fallback |
| Modify | `atlas-eye/src/lib/types.ts` | Add `LeadMatchType`, `SearchHit` |
| Modify | `atlas-eye/src/lib/utils.ts` | Add `renderSnippet(content, query)` (HTML-escaped `<mark>` highlight) |
| Modify | `atlas-eye/src/components/Chat/LeadList.tsx:182-192` | Swap `.filter()` for `useLeadSearch` result; new ordering |
| Modify | `atlas-eye/src/components/Chat/LeadListItem.tsx` | Accept optional `hit?: SearchHit`; render snippet when `matchType === 'message'` |

Files touched together ship in the same commit. Each task below ends with a commit step.

---

## Task 1 — Database migration: extensions and helper functions

**Files:**
- Create: `database/026_lead_search.sql`

- [ ] **Step 1: Create the migration file with extension + immutable helpers only (no indexes or RPC yet, so we can commit in small steps)**

```sql
-- 026_lead_search.sql
-- Part 1/3: extensions and immutable helpers used by indexes and RPC.

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- Phone normalization — strip everything except digits.
-- IMMUTABLE + PARALLEL SAFE so it can back an expression index.
CREATE OR REPLACE FUNCTION public.leads_phone_digits(p text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g');
$$;

-- Accent + case normalization. Wraps extensions.unaccent in a SQL function
-- marked IMMUTABLE (Supabase-accepted pattern); backs the trigram indexes.
CREATE OR REPLACE FUNCTION public.norm_text(p text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT extensions.unaccent('unaccent', lower(coalesce(p, '')));
$$;

GRANT EXECUTE ON FUNCTION public.leads_phone_digits(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.norm_text(text) TO authenticated, anon;
```

- [ ] **Step 2: Apply the migration to the dev database**

Run (from project root, with `.env` providing `DATABASE_URL` or equivalent psql connection):
```bash
psql "$DATABASE_URL" -f database/026_lead_search.sql
```
Expected: `CREATE EXTENSION` + two `CREATE FUNCTION` + two `GRANT` confirmations, no errors.

- [ ] **Step 3: Smoke-test the helpers in psql**

Run:
```bash
psql "$DATABASE_URL" -c "SELECT public.leads_phone_digits('+55 (84) 91234-5678');"
psql "$DATABASE_URL" -c "SELECT public.norm_text('Alcinéia DA SILVA');"
```
Expected:
- `leads_phone_digits` returns `5584912345678`.
- `norm_text` returns `alcineia da silva` (no accent, lowercased).

- [ ] **Step 4: Commit**

```bash
git add database/026_lead_search.sql
git commit -m "feat(db): add unaccent + immutable helpers for lead search (1/3)"
```

---

## Task 2 — Database migration: partial GIN trigram indexes

**Files:**
- Modify: `database/026_lead_search.sql` (append)

- [ ] **Step 1: Append the four indexes to the migration file**

```sql
-- Part 2/3: GIN trigram indexes. CONCURRENTLY avoids locking production tables.
-- Must be run outside a transaction block. If applying via psql -f, keep these
-- statements at top-level (no BEGIN/COMMIT wrapping).

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_title_trgm
  ON public.leads USING gin (public.norm_text(title) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_email_trgm
  ON public.leads USING gin (public.norm_text(email) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_phone_digits_trgm
  ON public.leads USING gin (public.leads_phone_digits(phone) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_activities_content_trgm
  ON public.lead_activities USING gin (public.norm_text(content) extensions.gin_trgm_ops)
  WHERE type IN ('whatsapp','email') AND content IS NOT NULL;
```

- [ ] **Step 2: Apply only the new statements**

`CREATE INDEX CONCURRENTLY` cannot run inside a transaction. Apply each statement individually:
```bash
psql "$DATABASE_URL" -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_title_trgm ON public.leads USING gin (public.norm_text(title) extensions.gin_trgm_ops) WHERE deleted_at IS NULL;"
psql "$DATABASE_URL" -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_email_trgm ON public.leads USING gin (public.norm_text(email) extensions.gin_trgm_ops) WHERE deleted_at IS NULL;"
psql "$DATABASE_URL" -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_phone_digits_trgm ON public.leads USING gin (public.leads_phone_digits(phone) extensions.gin_trgm_ops) WHERE deleted_at IS NULL;"
psql "$DATABASE_URL" -c "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_activities_content_trgm ON public.lead_activities USING gin (public.norm_text(content) extensions.gin_trgm_ops) WHERE type IN ('whatsapp','email') AND content IS NOT NULL;"
```
Expected: each returns `CREATE INDEX` with no error. Build time scales with row count; wait for each to finish.

- [ ] **Step 3: Verify indexes exist and are valid**

Run:
```bash
psql "$DATABASE_URL" -c "SELECT indexrelid::regclass AS index, indisvalid FROM pg_index WHERE indexrelid::regclass::text LIKE '%_trgm';"
```
Expected: 4 rows, all `indisvalid = t`.

- [ ] **Step 4: Commit**

```bash
git add database/026_lead_search.sql
git commit -m "feat(db): add partial GIN trigram indexes for lead search (2/3)"
```

---

## Task 3 — Database migration: `search_leads` RPC

**Files:**
- Modify: `database/026_lead_search.sql` (append)

- [ ] **Step 1: Append the RPC to the migration file**

```sql
-- Part 3/3: search_leads RPC.
-- SECURITY INVOKER so RLS on leads/lead_activities still applies.
-- view_own_only is enforced explicitly because RLS only checks org membership.

CREATE OR REPLACE FUNCTION public.search_leads(
  p_org uuid,
  p_q text,
  p_view_own_only boolean DEFAULT false,
  p_member_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  lead_id uuid,
  match_type text,         -- 'title' | 'email' | 'phone' | 'message'
  snippet text,
  matched_at timestamptz,
  lead jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
  v_term text := public.norm_text(p_q);
  v_digits text := public.leads_phone_digits(p_q);
BEGIN
  IF length(v_term) < 3 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH lead_hits AS (
    SELECT l.id AS lead_id,
           CASE
             WHEN public.norm_text(l.title) LIKE '%'||v_term||'%' THEN 'title'
             WHEN public.norm_text(l.email) LIKE '%'||v_term||'%' THEN 'email'
             ELSE 'phone'
           END AS match_type,
           NULL::text AS snippet,
           NULL::timestamptz AS matched_at,
           to_jsonb(l.*) AS lead_json
    FROM public.leads l
    WHERE l.organization_id = p_org
      AND l.deleted_at IS NULL
      AND (NOT p_view_own_only OR l.owner_member_id = p_member_id)
      AND (
        public.norm_text(l.title) LIKE '%'||v_term||'%'
        OR public.norm_text(l.email) LIKE '%'||v_term||'%'
        OR (length(v_digits) >= 3
            AND public.leads_phone_digits(l.phone) LIKE '%'||v_digits||'%')
      )
  ),
  msg_hits AS (
    SELECT DISTINCT ON (a.lead_id)
           a.lead_id AS lead_id,
           'message'::text AS match_type,
           a.content AS snippet,
           a.created_at AS matched_at,
           to_jsonb(l.*) AS lead_json
    FROM public.lead_activities a
    JOIN public.leads l
      ON l.id = a.lead_id
     AND l.organization_id = a.organization_id
    WHERE a.organization_id = p_org
      AND a.type IN ('whatsapp','email')
      AND a.content IS NOT NULL
      AND public.norm_text(a.content) LIKE '%'||v_term||'%'
      AND l.deleted_at IS NULL
      AND (NOT p_view_own_only OR l.owner_member_id = p_member_id)
    ORDER BY a.lead_id, a.created_at DESC
  )
  SELECT lead_id, match_type, snippet, matched_at, lead_json
  FROM lead_hits
  UNION ALL
  SELECT lead_id, match_type, snippet, matched_at, lead_json
  FROM msg_hits
  WHERE lead_id NOT IN (SELECT lead_id FROM lead_hits)
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_leads(uuid, text, boolean, uuid, int) TO authenticated;
```

- [ ] **Step 2: Apply the RPC to the database**

Run:
```bash
psql "$DATABASE_URL" -c "$(sed -n '/CREATE OR REPLACE FUNCTION public.search_leads/,/TO authenticated;/p' database/026_lead_search.sql)"
```
Or simpler, re-apply the whole file — the helpers are idempotent and indexes use `IF NOT EXISTS`:
```bash
psql "$DATABASE_URL" -f database/026_lead_search.sql
```
Expected: `CREATE FUNCTION` + `GRANT`, no errors. `CREATE INDEX CONCURRENTLY` will emit warnings if wrapped in a tx — if that happens, comment out the index block temporarily and re-run.

- [ ] **Step 3: Manual sanity check via psql**

Pick a real organization id from your dev DB (`SELECT id FROM organizations LIMIT 1;`), then:
```bash
psql "$DATABASE_URL" -c "SELECT match_type, snippet, lead->>'title' FROM public.search_leads('<org-uuid>'::uuid, 'al', false, null, 20);"
```
Expected: empty result (term has only 2 chars → RPC early-returns).
```bash
psql "$DATABASE_URL" -c "SELECT match_type, snippet, lead->>'title' FROM public.search_leads('<org-uuid>'::uuid, 'alc', false, null, 20);"
```
Expected: any leads whose normalized title/email/phone-digits contain `alc`, plus leads with messages containing it.

- [ ] **Step 4: Commit**

```bash
git add database/026_lead_search.sql
git commit -m "feat(db): add search_leads RPC with view_own_only + unaccent (3/3)"
```

---

## Task 4 — SQL smoke test script

**Files:**
- Create: `scripts/test-search-leads.ts`

- [ ] **Step 1: Inspect an existing test script for convention**

Open `scripts/test-rls.ts` or `scripts/test-query.ts`. Note: they load `.env`, create a Supabase client with the service-role key, run assertions, `console.log` outcomes, and `process.exit(1)` on failure. Follow the exact same pattern.

- [ ] **Step 2: Write the test script**

```ts
// scripts/test-search-leads.ts
// Smoke test for public.search_leads RPC.
// Run with: npx tsx scripts/test-search-leads.ts

import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!
const testOrgId = process.env.TEST_ORG_ID!

if (!url || !serviceKey || !testOrgId) {
  console.error('Missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / TEST_ORG_ID')
  process.exit(1)
}

const sb = createClient(url, serviceKey, { auth: { persistSession: false } })

let failures = 0
function check(label: string, cond: boolean, extra?: unknown) {
  if (cond) {
    console.log(`PASS  ${label}`)
  } else {
    console.error(`FAIL  ${label}`, extra ?? '')
    failures++
  }
}

async function rpc(q: string, viewOwnOnly = false, memberId: string | null = null, limit = 50) {
  const { data, error } = await sb.rpc('search_leads', {
    p_org: testOrgId,
    p_q: q,
    p_view_own_only: viewOwnOnly,
    p_member_id: memberId,
    p_limit: limit,
  })
  if (error) throw error
  return data ?? []
}

async function main() {
  // 1. q < 3 chars → empty
  const short = await rpc('al')
  check('q < 3 chars returns empty', short.length === 0, short)

  // 2. wrong org → empty (RLS)
  const { data: wrongOrg } = await sb.rpc('search_leads', {
    p_org: '00000000-0000-0000-0000-000000000000',
    p_q: 'xxx',
    p_view_own_only: false,
    p_member_id: null,
    p_limit: 10,
  })
  check('nonexistent org returns empty', !wrongOrg || wrongOrg.length === 0)

  // 3. accent-insensitive: seed a lead named Alcinéia and search for Alcineia
  const { data: inserted } = await sb.from('leads').insert({
    organization_id: testOrgId,
    title: 'Alcinéia Teste',
    phone: '+55 (84) 91234-5678',
  }).select('id').single()
  if (!inserted) throw new Error('could not insert test lead')
  try {
    const hits = await rpc('alcineia')
    check(
      'accent-insensitive name match',
      hits.some((h: any) => h.lead_id === inserted.id && h.match_type === 'title'),
      hits,
    )

    // 4. phone digits match (substring of digits-only)
    const phoneHits = await rpc('91234567')
    check(
      'phone digits substring match',
      phoneHits.some((h: any) => h.lead_id === inserted.id && h.match_type === 'phone'),
      phoneHits,
    )

    // 5. message content match with snippet + dedup by lead_id
    for (let i = 0; i < 3; i++) {
      await sb.from('lead_activities').insert({
        organization_id: testOrgId,
        lead_id: inserted.id,
        type: 'whatsapp',
        content: `Mensagem ${i} sobre procedimento XYZTESTE agendado`,
      })
    }
    const msgHits = await rpc('xyzteste')
    const mine = msgHits.filter((h: any) => h.lead_id === inserted.id)
    check('message match returns exactly one row per lead', mine.length === 1, mine)
    check('message match has snippet', mine[0]?.snippet?.includes('XYZTESTE'))
    check('message match has matched_at', !!mine[0]?.matched_at)
    check('message match uses match_type=message', mine[0]?.match_type === 'message')

    // 6. view_own_only filter — foreign member sees nothing
    const foreignHits = await rpc('alcineia', true, '00000000-0000-0000-0000-000000000000')
    check(
      'view_own_only with foreign member excludes lead',
      !foreignHits.some((h: any) => h.lead_id === inserted.id),
      foreignHits,
    )
  } finally {
    await sb.from('lead_activities').delete().eq('lead_id', inserted.id)
    await sb.from('leads').delete().eq('id', inserted.id)
  }

  if (failures > 0) {
    console.error(`\n${failures} failure(s)`)
    process.exit(1)
  }
  console.log('\nAll checks passed')
}

main().catch(err => { console.error(err); process.exit(1) })
```

- [ ] **Step 3: Run the test**

Make sure `.env` has `TEST_ORG_ID` (a real dev org UUID). Then:
```bash
npx tsx scripts/test-search-leads.ts
```
Expected: 8 `PASS` lines, final `All checks passed`, exit 0. If any fail, the failure prints the returned rows for debugging.

- [ ] **Step 4: Commit**

```bash
git add scripts/test-search-leads.ts
git commit -m "test(db): smoke tests for search_leads RPC"
```

---

## Task 5 — Shared types: `LeadMatchType` and `SearchHit`

**Files:**
- Modify: `atlas-eye/src/lib/types.ts` (append at the end, before any default export if present)

- [ ] **Step 1: Open `atlas-eye/src/lib/types.ts` and confirm `LeadWithOwner` is exported.** It is referenced by `LeadsContext`, so it must already exist. If missing, stop — the design assumes it exists.

- [ ] **Step 2: Append the new types**

```ts
// Lead search types — used by useLeadSearch, /api/leads/search, LeadList, LeadListItem.
export type LeadMatchType = 'title' | 'email' | 'phone' | 'message'

export interface SearchHit {
  lead: LeadWithOwner
  matchType: LeadMatchType
  snippet?: string
  matchedAt?: string // ISO
}
```

- [ ] **Step 3: Type-check**

Run:
```bash
cd atlas-eye && npm run type-check
```
Expected: exit 0, no errors.

- [ ] **Step 4: Commit**

```bash
git add atlas-eye/src/lib/types.ts
git commit -m "feat(types): add LeadMatchType and SearchHit"
```

---

## Task 6 — `renderSnippet` utility

**Files:**
- Modify: `atlas-eye/src/lib/utils.ts` (append)

- [ ] **Step 1: Read the bottom of `atlas-eye/src/lib/utils.ts`** to see existing exports (e.g., `formatPhone`). Match the style.

- [ ] **Step 2: Append `renderSnippet` and its helpers**

```ts
// Accent + case normalization mirroring SQL norm_text — used only for locating
// the match position. Output of renderSnippet is HTML-safe.
const stripAccents = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
const normalizeForMatch = (s: string) => stripAccents(s).toLowerCase()

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')

/**
 * Returns an HTML string with the first occurrence of `query` inside `content`
 * wrapped in <mark>, truncated to a window of ~60 chars around the match.
 * Escapes HTML before wrapping, so the result is safe for dangerouslySetInnerHTML.
 * If no match, returns the content truncated to 60 chars with ellipsis.
 */
export function renderSnippet(content: string, query: string): string {
  if (!content) return ''
  const trimmed = query.trim()
  if (!trimmed) return escapeHtml(content.length > 60 ? content.slice(0, 60) + '…' : content)

  const normContent = normalizeForMatch(content)
  const normQuery = normalizeForMatch(trimmed)
  const idx = normContent.indexOf(normQuery)

  if (idx === -1) {
    return escapeHtml(content.length > 60 ? content.slice(0, 60) + '…' : content)
  }

  const matchEnd = idx + trimmed.length
  const window = 60
  const start = Math.max(0, idx - Math.floor((window - trimmed.length) / 2))
  const end = Math.min(content.length, start + window)

  const before = escapeHtml(content.slice(start, idx))
  const match = escapeHtml(content.slice(idx, matchEnd))
  const after = escapeHtml(content.slice(matchEnd, end))

  const prefix = start > 0 ? '…' : ''
  const suffix = end < content.length ? '…' : ''

  return `${prefix}${before}<mark>${match}</mark>${after}${suffix}`
}
```

- [ ] **Step 3: Manual sanity check via a throwaway Node REPL**

Run:
```bash
cd atlas-eye && node -e "const { renderSnippet } = require('./src/lib/utils.ts'); console.log(renderSnippet('Confirmo a consulta para Alcinéia na sexta-feira','alcineia'))"
```
(If that fails because utils imports ESM-only code, create a scratch `.mjs` importing from the TS source via `tsx`: `npx tsx -e "..."`.)

Expected output contains `<mark>Alcinéia</mark>` surrounded by adjacent text and `…` at boundaries.

- [ ] **Step 4: Type-check**

Run:
```bash
cd atlas-eye && npm run type-check
```
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add atlas-eye/src/lib/utils.ts
git commit -m "feat(utils): add renderSnippet with HTML-safe mark highlighting"
```

---

## Task 7 — API route `POST /api/leads/search`

**Files:**
- Create: `atlas-eye/src/app/api/leads/search/route.ts`

- [ ] **Step 1: Read `atlas-eye/src/app/api/leads/route.ts`** to copy its exact auth/org/permissions plumbing. Do not invent a new pattern.

- [ ] **Step 2: Write the route handler**

```ts
// atlas-eye/src/app/api/leads/search/route.ts
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'   // adjust import if your project uses a different helper
import type { LeadWithOwner } from '@/lib/types'
import type { SearchHit, LeadMatchType } from '@/lib/types'

export const dynamic = 'force-dynamic'

interface SearchBody {
  q?: string
  limit?: number
}

export async function POST(req: NextRequest) {
  const body: SearchBody = await req.json().catch(() => ({} as SearchBody))
  const q = (body.q ?? '').trim()
  const limit = Math.min(Math.max(body.limit ?? 50, 1), 100)

  if (q.length < 3) {
    return NextResponse.json({ error: 'q must be at least 3 characters' }, { status: 400 })
  }

  const supabase = await createClient()
  const { data: sess } = await supabase.auth.getUser()
  if (!sess?.user) {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }

  // Resolve active org + permissions — mirror /api/leads/route.ts exactly.
  // Replace the following block with whatever the existing route uses.
  const { data: member } = await supabase
    .from('organization_members')
    .select('id, organization_id, permissions:roles(permissions)')
    .eq('user_id', sess.user.id)
    .limit(1)
    .maybeSingle()

  if (!member?.organization_id) {
    return NextResponse.json({ error: 'no active organization' }, { status: 400 })
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const perms = (member as any).permissions?.permissions ?? {}
  const viewOwnOnly = Boolean(perms?.leads?.view_own_only)

  const { data, error } = await supabase.rpc('search_leads', {
    p_org: member.organization_id,
    p_q: q,
    p_view_own_only: viewOwnOnly,
    p_member_id: viewOwnOnly ? member.id : null,
    p_limit: limit,
  })

  if (error) {
    console.error('[api/leads/search] RPC error', error)
    return NextResponse.json({ error: 'search failed' }, { status: 500 })
  }

  const hits: SearchHit[] = (data ?? []).map((row: {
    lead_id: string
    match_type: LeadMatchType
    snippet: string | null
    matched_at: string | null
    lead: LeadWithOwner
  }) => ({
    lead: row.lead,
    matchType: row.match_type,
    snippet: row.snippet ?? undefined,
    matchedAt: row.matched_at ?? undefined,
  }))

  return NextResponse.json({ hits })
}
```

**Note:** if `@/lib/supabase/server` or the org-resolution shape differs in your codebase, copy whatever `atlas-eye/src/app/api/leads/route.ts` does. The important invariants: (a) user authenticated, (b) active org id is known, (c) `view_own_only` is read from the caller's role permissions, (d) `p_member_id` is the caller's `organization_members.id`, not `user.id`.

- [ ] **Step 3: Type-check**

```bash
cd atlas-eye && npm run type-check
```
Expected: exit 0.

- [ ] **Step 4: Manual cURL check against a running dev server**

In one terminal:
```bash
cd atlas-eye && npm run dev
```

In another, with a valid session cookie (export it from the browser devtools → `cookie` header):
```bash
curl -X POST http://localhost:3000/api/leads/search \
  -H 'Content-Type: application/json' \
  -H "Cookie: <paste-session-cookie>" \
  -d '{"q":"al"}'
```
Expected: `{"error":"q must be at least 3 characters"}` with 400.

```bash
curl -X POST http://localhost:3000/api/leads/search \
  -H 'Content-Type: application/json' \
  -H "Cookie: <paste-session-cookie>" \
  -d '{"q":"alcineia"}'
```
Expected: `{"hits":[...]}` with 200, each hit has `lead`, `matchType`, optional `snippet`/`matchedAt`.

- [ ] **Step 5: Commit**

```bash
git add atlas-eye/src/app/api/leads/search/route.ts
git commit -m "feat(api): POST /api/leads/search using search_leads RPC"
```

---

## Task 8 — `useLeadSearch` hook

**Files:**
- Create: `atlas-eye/src/hooks/useLeadSearch.ts`
- Modify: `atlas-eye/src/hooks/index.ts` (if it re-exports hooks — check first)

- [ ] **Step 1: Check if `atlas-eye/src/hooks/index.ts` re-exports existing hooks.** If it does, plan to add `useLeadSearch` there. If not, skip that edit.

- [ ] **Step 2: Write the hook**

```ts
// atlas-eye/src/hooks/useLeadSearch.ts
'use client'

import { useEffect, useRef, useState } from 'react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import type { LeadWithOwner, SearchHit } from '@/lib/types'

const MIN_SERVER_CHARS = 3
const DEBOUNCE_MS = 250

// Mirror SQL norm_text: strip accents + lowercase.
const norm = (s: string | null | undefined) =>
  (s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()

const digits = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '')

interface UseLeadSearchResult {
  results: SearchHit[]
  loading: boolean
  error: Error | null
  mode: 'client' | 'server'
}

export function useLeadSearch(query: string): UseLeadSearchResult {
  const { leads } = useLeadsContext()
  const [serverHits, setServerHits] = useState<SearchHit[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const requestIdRef = useRef(0)
  const abortRef = useRef<AbortController | null>(null)

  const trimmed = query.trim()

  // Server-side search for q >= 3 chars, debounced.
  useEffect(() => {
    if (trimmed.length < MIN_SERVER_CHARS) {
      setServerHits(null)
      setError(null)
      setLoading(false)
      abortRef.current?.abort()
      return
    }

    const myRequestId = ++requestIdRef.current
    abortRef.current?.abort()
    const ctl = new AbortController()
    abortRef.current = ctl

    setLoading(true)
    const timer = setTimeout(async () => {
      try {
        const res = await fetch('/api/leads/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ q: trimmed }),
          signal: ctl.signal,
        })
        if (!res.ok) throw new Error(`search failed (${res.status})`)
        const { hits } = (await res.json()) as { hits: SearchHit[] }
        if (requestIdRef.current !== myRequestId) return // stale
        setServerHits(hits)
        setError(null)
      } catch (err) {
        if ((err as { name?: string }).name === 'AbortError') return
        if (requestIdRef.current !== myRequestId) return
        setError(err as Error)
        setServerHits(null) // fall back to client-side below
      } finally {
        if (requestIdRef.current === myRequestId) setLoading(false)
      }
    }, DEBOUNCE_MS)

    return () => {
      clearTimeout(timer)
      ctl.abort()
    }
  }, [trimmed])

  // Client-side path.
  if (trimmed.length === 0) {
    const results: SearchHit[] = leads.map((lead: LeadWithOwner) => ({ lead, matchType: 'title' as const }))
    return { results, loading: false, error: null, mode: 'client' }
  }

  if (trimmed.length < MIN_SERVER_CHARS || serverHits === null) {
    const nq = norm(trimmed)
    const dq = digits(trimmed)
    const results: SearchHit[] = []
    for (const lead of leads) {
      if (norm(lead.title).includes(nq)) { results.push({ lead, matchType: 'title' }); continue }
      if (norm(lead.email).includes(nq)) { results.push({ lead, matchType: 'email' }); continue }
      if (dq.length >= 3 && digits(lead.phone).includes(dq)) { results.push({ lead, matchType: 'phone' }); continue }
    }
    return { results, loading, error, mode: 'client' }
  }

  return { results: serverHits, loading, error, mode: 'server' }
}
```

- [ ] **Step 3: (If applicable) Export from `atlas-eye/src/hooks/index.ts`**

Add a line like `export { useLeadSearch } from './useLeadSearch'` — only if the index barrel exists.

- [ ] **Step 4: Type-check**

```bash
cd atlas-eye && npm run type-check
```
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add atlas-eye/src/hooks/useLeadSearch.ts atlas-eye/src/hooks/index.ts
git commit -m "feat(hooks): useLeadSearch with threshold, debounce, fallback"
```

---

## Task 9 — `LeadListItem` snippet rendering

**Files:**
- Modify: `atlas-eye/src/components/Chat/LeadListItem.tsx`

- [ ] **Step 1: Read the current `LeadListItem` component fully** to understand its prop shape, className conventions, and where the last-message preview is rendered.

- [ ] **Step 2: Add the optional `hit` and `query` props and conditional snippet render**

Near the top of the props interface:

```tsx
import type { SearchHit } from '@/lib/types'
import { renderSnippet } from '@/lib/utils'

interface LeadListItemProps {
  // ...existing props...
  hit?: SearchHit
  query?: string
}
```

Just below the existing last-message-preview line (find the element that renders `lead.last_message` or similar — if there is no existing preview, render this as the only preview):

```tsx
{props.hit?.matchType === 'message' && props.hit.snippet && (
  <div className="text-xs text-gray-500 italic mt-0.5 line-clamp-1">
    <span className="text-blue-600 mr-1">↩</span>
    <span dangerouslySetInnerHTML={{ __html: renderSnippet(props.hit.snippet, props.query ?? '') }} />
  </div>
)}
```

If `hit` is absent (non-search state), the component renders exactly as before — fully backward-compatible.

- [ ] **Step 3: Type-check**

```bash
cd atlas-eye && npm run type-check
```
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add atlas-eye/src/components/Chat/LeadListItem.tsx
git commit -m "feat(chat): render message-match snippet in LeadListItem"
```

---

## Task 10 — Wire `LeadList` to `useLeadSearch`

**Files:**
- Modify: `atlas-eye/src/components/Chat/LeadList.tsx` (replace lines 182-192 plus the loop that renders `visibleLeads`)

- [ ] **Step 1: Replace the `filteredLeads`/`visibleLeads` block**

Locate `atlas-eye/src/components/Chat/LeadList.tsx:182-194`. Replace:

```ts
const filteredLeads = leads
  .filter(l => l.title.toLowerCase().includes(search.toLowerCase()))
  .sort((a, b) => {
    if (a.is_pinned && !b.is_pinned) return -1
    if (!a.is_pinned && b.is_pinned) return 1
    const timeA = new Date(a.last_activity_at || a.created_at).getTime()
    const timeB = new Date(b.last_activity_at || b.created_at).getTime()
    return timeB - timeA
  })

const visibleLeads = filteredLeads.slice(0, displayLimit)
```

With:

```ts
import { useLeadSearch } from '@/hooks/useLeadSearch'
import type { SearchHit } from '@/lib/types'

// ... inside the component body, replacing the old block:
const { results: searchResults, loading: searching } = useLeadSearch(search)

const filteredHits: SearchHit[] = [...searchResults].sort((a, b) => {
  if (a.lead.is_pinned !== b.lead.is_pinned) return a.lead.is_pinned ? -1 : 1
  const rank = (h: SearchHit) => (h.matchType === 'message' ? 1 : 0)
  if (rank(a) !== rank(b)) return rank(a) - rank(b)
  const ta = new Date(a.lead.last_activity_at || a.lead.created_at).getTime()
  const tb = new Date(b.lead.last_activity_at || b.lead.created_at).getTime()
  return tb - ta
})

const visibleHits = filteredHits.slice(0, displayLimit)
```

- [ ] **Step 2: Update the render loop to pass `hit` + `query` to `LeadListItem`**

Find the existing `filteredLeads.length === 0` branch and the `visibleLeads.map((lead) => ...)` loop. Replace them with:

```tsx
{filteredHits.length === 0 ? (
  <div className="flex items-center justify-center h-full text-gray-500 text-sm">
    {searching ? 'Buscando…' : 'Nenhum lead encontrado'}
  </div>
) : (
  <div className="flex flex-col min-h-full">
    {visibleHits.map((hit) => (
      <LeadListItem
        key={hit.lead.id}
        lead={hit.lead}
        hit={hit}
        query={search}
        // ...keep any other existing props (selected state, onClick, onContextMenu, etc.)
      />
    ))}
  </div>
)}
```

Keep every other pre-existing prop on `LeadListItem` (selection, click, context menu, etc.) — only `hit` and `query` are new.

- [ ] **Step 3: Remove `.import` of `LeadWithOwner` if it becomes unused**

Run `npm run lint` after the edit; resolve any unused-import warnings.

- [ ] **Step 4: Type-check + lint**

```bash
cd atlas-eye && npm run type-check && npm run lint
```
Expected: exit 0 for both.

- [ ] **Step 5: Commit**

```bash
git add atlas-eye/src/components/Chat/LeadList.tsx
git commit -m "feat(chat): wire LeadList to useLeadSearch (name/phone/email/message)"
```

---

## Task 11 — Manual browser QA

**Files:** none (QA only)

- [ ] **Step 1: Start the dev server**

```bash
cd atlas-eye && npm run dev
```
Open `http://localhost:3000/chat`.

- [ ] **Step 2: Reproduce the original bugs and confirm they are fixed**

For each row, type into the Chat sidebar search, observe, confirm:

| # | Input | Expected |
|---|---|---|
| 1 | `al` (2 chars) | Instant client filter; shows leads whose name/email/phone-digits contain "al". No network request. |
| 2 | `alc` (3 chars) | ~250ms later a `POST /api/leads/search` fires (check DevTools Network). Results appear. |
| 3 | `Alcineia` (client has stored `Alcinéia`) | Lead appears. This is the core bug fix. |
| 4 | `84617668` | A lead whose phone contains those digits appears. Bug fix #2. |
| 5 | A word known to appear inside a WhatsApp message but not in any lead name | The lead appears with an italic snippet below its last-message preview, with the matched term wrapped in a `<mark>`. |
| 6 | Pin a lead, then search for a word present in a non-pinned lead's message | Pinned lead still shows first (pinned beats match type). |
| 7 | A query matching both a lead's `title` and some other lead's message | Contact-match lead ranks above message-match lead. |
| 8 | Clear the search | Full lead list returns, ordering identical to before this change. |

- [ ] **Step 3: Verify `view_own_only` respects permission**

Using a user whose role has `leads.view_own_only = true`:
- Search for a known lead **not** owned by that user → should not appear, even if matching.
- Search for a message inside a lead not owned by that user → should not appear.

- [ ] **Step 4: Simulate API failure and confirm graceful fallback**

In DevTools Network, block `POST /api/leads/search`. Type a 3+ char query.
- The list should fall back to client-side filtering on whatever is in `LeadsContext` (same behavior as 1-2 char search).
- No crash, no broken empty state.

- [ ] **Step 5: Confirm no regressions elsewhere**

- Open `GlobalSearch` (top bar) and search for a lead by phone — it still works (legacy route untouched).
- Pipeline Kanban still loads and reorders (no changes to `LeadsContext`).

- [ ] **Step 6: Commit the manual QA record**

Optional — add a short bullet to `progress.md` or the relevant STATUS file recording the date/commit of rollout. This is outside git tracking; skip if not part of your flow.

---

## Task 12 — Final verification and documentation close-out

**Files:** none (verification only)

- [ ] **Step 1: Re-run the SQL smoke test**

```bash
npx tsx scripts/test-search-leads.ts
```
Expected: `All checks passed`.

- [ ] **Step 2: Full type-check + lint**

```bash
cd atlas-eye && npm run type-check && npm run lint
```
Expected: exit 0 for both.

- [ ] **Step 3: Build**

```bash
cd atlas-eye && npm run build
```
Expected: successful production build with no type errors and no unused-export warnings related to this change.

- [ ] **Step 4: Update status docs to mark the initiative `shipped`**

Flip the "design approved, plan pending" markers added in the previous parallel-docs round:
- `docs/audit-2026-04-13/ROADMAP.md`: move the checklist item to "done".
- `docs/audit-2026-04-13/PROJECT_STATUS.md`: replace "awaiting implementation" with "shipped YYYY-MM-DD".
- `atlas-eye/STATUS.md`: flip the checkbox to `[x]`.

Commit:
```bash
git add docs/audit-2026-04-13/ROADMAP.md docs/audit-2026-04-13/PROJECT_STATUS.md atlas-eye/STATUS.md
git commit -m "docs: mark lead filter overhaul shipped"
```

---

## Self-review notes (inline fixes applied)

- Verified every spec requirement maps to a task: hybrid threshold (Task 8), `view_own_only` enforcement (Tasks 3, 7), accent insensitivity (Tasks 1, 3, 6, 8), phone digits normalization (Tasks 1, 3, 8), message snippet with highlight (Tasks 6, 9), pinned-first ordering (Task 10), fallback on API error (Tasks 8, 11), non-interference with `GlobalSearch` (Task 11).
- Spec lists "Testing" with Vitest + MSW. Project has no test framework installed (`package.json` has no test tooling). Plan substitutes a psql-based SQL test script (Task 4) plus a structured manual QA checklist (Task 11). Adding Vitest is a separate initiative and stays out of this plan per YAGNI.
- Types referenced across tasks are consistent: `SearchHit`/`LeadMatchType` defined in Task 5 and used by Tasks 7, 8, 9, 10 with identical shapes.
- No placeholders, no "TBD", no "similar to earlier task" references.
