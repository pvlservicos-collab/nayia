-- 026_lead_search.sql
-- Lead search infrastructure: extensions, immutable helpers, partial GIN trigram
-- indexes, and the search_leads RPC used by POST /api/leads/search.
--
-- Spec:  docs/superpowers/specs/2026-04-13-lead-filter-design.md
-- Plan:  docs/superpowers/plans/2026-04-13-lead-filter.md
--
-- How to apply:
--   Option A — Supabase SQL Editor: paste this whole file EXCEPT the
--     CREATE INDEX CONCURRENTLY block (SQL Editor wraps statements in a
--     transaction, which CONCURRENTLY forbids). Run the rest first, then
--     run each CREATE INDEX CONCURRENTLY line one-by-one.
--   Option B — psql: `psql "$DATABASE_URL" -f database/026_lead_search.sql`
--     fine — psql streams statements outside a tx.

-- =========================================================
-- Part 1/3: extensions and immutable helpers
-- =========================================================

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- Phone normalization — strip everything except digits.
-- IMMUTABLE + PARALLEL SAFE so it can back an expression index.
CREATE OR REPLACE FUNCTION public.leads_phone_digits(p text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g');
$$;

-- Accent + case normalization. Wraps extensions.unaccent in a SQL function
-- marked IMMUTABLE (Supabase-accepted pattern) so it can back trigram indexes.
CREATE OR REPLACE FUNCTION public.norm_text(p text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path = extensions, public
AS $$
  SELECT extensions.unaccent('extensions.unaccent'::regdictionary, lower(coalesce(p, '')));
$$;

GRANT EXECUTE ON FUNCTION public.leads_phone_digits(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.norm_text(text) TO authenticated, anon;

-- =========================================================
-- Part 2/3: partial GIN trigram indexes
-- NOTE: must run OUTSIDE a transaction. In Supabase SQL Editor, run each
-- of these four statements individually. In psql -f, they run top-level.
-- =========================================================

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

-- =========================================================
-- Part 3/3: search_leads RPC
-- SECURITY INVOKER so RLS on leads/lead_activities still applies.
-- view_own_only is enforced explicitly because RLS checks only org membership.
-- =========================================================

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
#variable_conflict use_column
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
