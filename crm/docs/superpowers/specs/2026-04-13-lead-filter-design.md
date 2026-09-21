# Lead Filter Overhaul — Design Spec

- **Date:** 2026-04-13
- **Owner:** atlas-eye
- **Area:** Chat sidebar (`LeadList`), Postgres search infra
- **Status:** Approved design, pending implementation plan

## Context

The Chat sidebar filter in `atlas-eye/src/components/Chat/LeadList.tsx:182` only searches `lead.title` with a client-side `.includes()`. This produces two reported failures:

1. Searching `"84617668"` (phone) returns no results — `phone` is not in the filter.
2. Searching `"Alcineia"` (existing name) returns no results — the lead is either outside the 1000-row Supabase default cap loaded by `LeadsContext`, or the stored name is accented (`Alcinéia`) and byte comparison fails.

The filter must also cover message history, since operators recall leads by what was said in the conversation.

## Goals

- Search by **name**, **phone** (digits-only normalized), **email**, and **WhatsApp/email message content**.
- Return the lead even when it is not in the client-loaded `LeadsContext` array (fixes the 1000-cap regression).
- Show a snippet of the matched message when the match is on content, with the matched term highlighted.
- Preserve current permission boundaries, including `view_own_only`.
- Keep Postgres cost bounded — no scans on every keystroke, no word-stemming overhead.

## Non-goals

- Searching tags, owner names, `custom_attributes`, or notes (`lead_activities.type='note'`).
- Paginating result sets beyond `LIMIT 50`.
- Highlighting inside the open `ChatWindow`.
- Replacing the existing `GlobalSearch` or `/api/leads?q=` endpoint.

## Architecture

```
 User types in LeadList search input
   │
   ├─ len(q) < 3   → client-side filter over LeadsContext.leads
   │                 (title / email / phone-digits), instant, 0 requests
   │
   └─ len(q) >= 3  → debounce 250ms → POST /api/leads/search
                      │
                      └─ Postgres RPC search_leads(p_org, p_q, p_view_own_only, p_member_id, p_limit)
                           ├─ CTE lead_hits:     ILIKE over unaccent(lower(title|email)) + phone digits
                           └─ CTE msg_hits:      ILIKE over unaccent(lower(content)) in ('whatsapp','email')
                             → DISTINCT ON (lead_id) ORDER BY created_at DESC
                           UNION ALL (msg_hits minus lead_hits)
                           LIMIT p_limit
                      │
                      └─ Returns full lead rows + { matchType, snippet?, matchedAt? }
```

Ordering in the UI: **pinned > contact match > message match > recency (`last_activity_at`)**.

## Database changes

New migration file `database/037_lead_search_indices.sql` (or next available number):

```sql
-- 1. Required extensions (pg_trgm already present in schema extensions)
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- 2. Stable immutable helper for phone normalization so the index expression
--    matches the query expression exactly. Must be IMMUTABLE for index use.
CREATE OR REPLACE FUNCTION public.leads_phone_digits(p text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g');
$$;

-- 3. Accent-insensitive, case-insensitive helper. IMMUTABLE requires a stable
--    unaccent dictionary — we use the default 'unaccent' dictionary.
CREATE OR REPLACE FUNCTION public.norm_text(p text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT extensions.unaccent('unaccent', lower(coalesce(p, '')));
$$;

-- 4. Trigram indexes (partial to keep small and relevant)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_title_trgm
  ON leads USING gin (public.norm_text(title) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_email_trgm
  ON leads USING gin (public.norm_text(email) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_leads_phone_digits_trgm
  ON leads USING gin (public.leads_phone_digits(phone) extensions.gin_trgm_ops)
  WHERE deleted_at IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_activities_content_trgm
  ON lead_activities USING gin (public.norm_text(content) extensions.gin_trgm_ops)
  WHERE type IN ('whatsapp','email') AND content IS NOT NULL;
```

Notes:
- `CREATE INDEX CONCURRENTLY` avoids locking production tables. Must run outside a transaction.
- Partial indexes keep them small — soft-deleted leads and `system/note/call` activities are excluded.
- The function `norm_text` is marked `IMMUTABLE` to be usable in expression indexes. The default `unaccent` dictionary is stable in practice, though technically it depends on a file; Postgres accepts this as immutable when wrapped in a SQL function — this is the common Supabase pattern.

## RPC: `search_leads`

```sql
CREATE OR REPLACE FUNCTION public.search_leads(
  p_org uuid,
  p_q text,
  p_view_own_only boolean DEFAULT false,
  p_member_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS TABLE (
  lead_id uuid,
  match_type text,        -- 'title' | 'email' | 'phone' | 'message'
  snippet text,
  matched_at timestamptz,
  lead jsonb              -- full lead row for hydration
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
    SELECT l.id,
           CASE
             WHEN public.norm_text(l.title) LIKE '%'||v_term||'%' THEN 'title'
             WHEN public.norm_text(l.email) LIKE '%'||v_term||'%' THEN 'email'
             ELSE 'phone'
           END AS match_type,
           NULL::text AS snippet,
           NULL::timestamptz AS matched_at,
           to_jsonb(l.*) AS lead_json
    FROM leads l
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
           a.lead_id AS id,
           'message'::text AS match_type,
           a.content AS snippet,
           a.created_at AS matched_at,
           to_jsonb(l.*) AS lead_json
    FROM lead_activities a
    JOIN leads l
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
  SELECT id, match_type, snippet, matched_at, lead_json
  FROM lead_hits
  UNION ALL
  SELECT id, match_type, snippet, matched_at, lead_json
  FROM msg_hits
  WHERE id NOT IN (SELECT id FROM lead_hits)
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_leads(uuid, text, boolean, uuid, int) TO authenticated;
```

Why `SECURITY INVOKER`: we want RLS on `leads` and `lead_activities` to still apply. The explicit `view_own_only` filter is defense in depth at the application layer, since RLS alone does not enforce ownership (see `database/002_rls_policies.sql:132`).

## API route: `POST /api/leads/search`

File: `atlas-eye/src/app/api/leads/search/route.ts`.

```ts
// Request:  { q: string, limit?: number }
// Response: { hits: Array<{ lead: LeadWithOwner, matchType, snippet?, matchedAt? }> }
// Errors:   400 if q.length < 3, 401 if no session, 500 on RPC failure
```

Implementation steps:
1. Read session + active organization (same pattern as `app/api/leads/route.ts`).
2. Resolve `permissions.leads.view_own_only` and the caller's `member.id`.
3. `supabase.rpc('search_leads', { p_org, p_q, p_view_own_only, p_member_id, p_limit })`.
4. Reshape rows into `{ lead, matchType, snippet, matchedAt }` by parsing `lead_json`.
5. Return JSON. Do not touch the legacy `/api/leads?q=` route — `GlobalSearch` still uses it.

## Frontend changes

### New hook: `atlas-eye/src/hooks/useLeadSearch.ts`

```ts
export function useLeadSearch(query: string): {
  results: SearchHit[]
  loading: boolean
  error: Error | null
  mode: 'client' | 'server'
}
```

Behavior:
- Trims + normalizes `query`.
- `length < 3`: filters `LeadsContext.leads` locally on `title`, `email`, and `leads_phone_digits(phone)` normalized. Returns `matchType` best-effort (`title`/`email`/`phone`). No `snippet`.
- `length >= 3`: debounces 250 ms, aborts the previous fetch via `AbortController`, increments a local request-id and discards out-of-order responses.
- On fetch error: falls back to the client-side path and surfaces an `error` (UI may show a toast once).

### `SearchHit` type

In `atlas-eye/src/lib/types.ts`:

```ts
export type LeadMatchType = 'title' | 'email' | 'phone' | 'message'

export interface SearchHit {
  lead: LeadWithOwner
  matchType: LeadMatchType
  snippet?: string
  matchedAt?: string // ISO
}
```

### `LeadList.tsx` refactor

Replace the current filter/sort block at `atlas-eye/src/components/Chat/LeadList.tsx:182-192`:

```ts
const { results, loading: searching } = useLeadSearch(search)

const filteredLeads = [...results].sort((a, b) => {
  if (a.lead.is_pinned !== b.lead.is_pinned) return a.lead.is_pinned ? -1 : 1
  const rank = (h: SearchHit) => (h.matchType === 'message' ? 1 : 0)
  if (rank(a) !== rank(b)) return rank(a) - rank(b)
  const ta = new Date(a.lead.last_activity_at || a.lead.created_at).getTime()
  const tb = new Date(b.lead.last_activity_at || b.lead.created_at).getTime()
  return tb - ta
})
```

When `search === ''`, `useLeadSearch` returns the full in-memory list mapped to `{ lead, matchType: 'title' }` so the existing render path works untouched.

Empty-state rules:
- `searching && results.length === 0` → small spinner in the list header; keep prior placeholder hidden.
- `!searching && results.length === 0` → "Nenhum lead encontrado".

### `LeadListItem.tsx` — snippet rendering

Accept an optional `hit?: SearchHit` prop. When `hit.matchType === 'message'` and `hit.snippet`, render below the existing last-message preview:

```tsx
{hit?.matchType === 'message' && hit.snippet && (
  <div className="text-xs text-gray-500 italic mt-0.5 line-clamp-1">
    <span className="text-blue-600">↩</span>{' '}
    <span dangerouslySetInnerHTML={{ __html: renderSnippet(hit.snippet, search) }} />
  </div>
)}
```

### Utility: `renderSnippet(content, query)`

New export in `atlas-eye/src/lib/utils.ts`:

- Lowercase + unaccent both sides to locate the match (mirrors server).
- Extract `~60` chars centered on the match.
- HTML-escape the snippet (`&`, `<`, `>`, `"`, `'`) then wrap the match in `<mark>`.
- Prefix/suffix with `…` when truncated.

HTML escape happens **before** wrapping; the `<mark>` tags are added after escape, so the `dangerouslySetInnerHTML` is safe by construction.

## Error handling

| Scenario | Behavior |
|---|---|
| API returns 500 | `useLeadSearch` falls back to client-only filter; single toast "Busca em mensagens indisponível". |
| API returns 400 (q too short) | Should not happen — client also guards. If it does, treat as empty results. |
| Session expired | Existing auth redirect path in the route kicks in (401). |
| Org switch mid-typing | `AbortController` cancels in-flight; `useLeadSearch` re-runs with new `organizationId`. |
| Lead soft-deleted between fetch and render | Filtered out by `deleted_at IS NULL` in RPC. |

## Testing

- **Unit — `renderSnippet`:** HTML escape, match at start/end/middle, multiple matches picks the first, no match returns input truncated.
- **Unit — `useLeadSearch`:** debounce timing, AbortController cancels stale, `length<3` stays client-side, error path falls back.
- **Integration — `LeadList` with MSW:** mocks `/api/leads/search`; verifies pinned > contact > message ordering; snippet rendered with `<mark>`; fallback on 500.
- **SQL — `search_leads`:**
  - wrong `p_org` returns zero (RLS).
  - `p_view_own_only=true` with another `p_member_id` excludes leads not owned.
  - accent-insensitive: row with `title='Alcinéia'` is returned for `p_q='Alcineia'`.
  - phone digits: stored `+55 (84) 91234-5678`, `p_q='84617668'` behaves correctly (non-match) and `p_q='91234567'` matches.
  - message deduplication: lead with 3 whatsapp matches returns one row, `snippet` from latest `created_at`.

## Migration and rollout

1. Ship the SQL migration first. Indexes are `CONCURRENTLY` so no downtime.
2. Ship the RPC and API route. Legacy filter still runs if frontend is old.
3. Ship the frontend (`useLeadSearch` + `LeadList` + `LeadListItem`).
4. No feature flag. Fallback path makes regression recoverable: if the API breaks, client-side filter still works for short queries and in-memory leads.

## Risks / open decisions

- `unaccent` marked `IMMUTABLE` inside a SQL wrapper is a widely used Supabase pattern but technically relies on a dictionary file. Accepted — no known production issue with the default `unaccent` dictionary.
- `LIMIT 50` without pagination: if users hit the cap, they see a truncated list. Acceptable for v1; surface "Refine a busca" hint is a future enhancement.
- Index build time on large `lead_activities`: `CONCURRENTLY` mitigates locking, but the build itself can take minutes. Should be monitored; a maintenance window is not required but is preferable.

## Documentation updates (part of this work)

- `progress.md`: add entry describing the filter overhaul.
- `README.md`: update feature list if it enumerates search capabilities.
- `API_REFERENCE.md`: document `POST /api/leads/search`.
- `schema.md`: document new indexes, `leads_phone_digits`, `norm_text`, and `search_leads`.
- `ARQUITECTURA_TECNICA.md`: diagram/section on the client-vs-server hybrid filter.
- Roadmap (wherever tracked — `task_plan.md` / `STATUS.md`): mark this initiative complete once shipped.

## Out of scope (explicit)

- Tag / owner / custom-field search.
- Message search inside the open conversation.
- Replacing `GlobalSearch` or `/api/leads?q=`.
- Server-side pagination of results.
