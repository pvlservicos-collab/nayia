\set ON_ERROR_STOP on
\pset pager off

-- =====================================================================
-- OS DOIS INDICES QUE FALTAVAM NO CRM (27/09/2026)
--
-- Tel: "verifica ... o carretagamento a otimziação".
--
-- As duas leituras mais quentes do app nao tinham indice:
--
--   1. A TIMELINE de uma conversa -- lead_id + ordem por data. Com 1.185
--      mensagens o Postgres varre tudo em 1ms e ninguem nota; com 100 mil
--      (dois meses do ritmo atual) a conversa comeca a demorar para abrir, e
--      e a tela que mais se usa no dia.
--   2. A LISTA de conversas -- organizacao + ultima atividade, que e
--      exatamente o ORDER BY da rota.
--
-- CONCURRENTLY para nao travar escrita enquanto cria (a Nay esta no ar).
-- =====================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS lead_activities_lead_created_idx
  ON lead_activities (lead_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS leads_org_atividade_idx
  ON leads (organization_id, last_activity_at DESC NULLS LAST)
  WHERE deleted_at IS NULL;

\echo '=== indices agora ==='
SELECT tablename, indexname FROM pg_indexes
 WHERE tablename IN ('leads','lead_activities') ORDER BY 1, 2;
