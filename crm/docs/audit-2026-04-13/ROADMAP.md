# Atlas Eye — Roadmap pós-auditoria

Plano priorizado em 3 janelas. Estimativas são horas-dev; ajuste com seu time.

---

## 🔥 Janela 0 — Hoje (bloqueador de produção) — ~6h

**Tudo aqui é crítico de segurança. Não deveria esperar.**

- [ ] **Rotacionar 8 tokens** listados em `SECURITY.md` (1h30)
  - Supabase service_role + anon
  - UAZAPI admin
  - Atlas Eye API token (`atl_*`)
  - SSH root password (ou ativar key-only)
  - npm auth token
  - Supabase PAT
  - Vercel OIDC
- [ ] **Expandir `.gitignore`** e remover arquivos sensíveis do tracking (30m)
- [ ] **Deletar migrations RLS bypass** (`018_test_bypass_rls.sql`, `022_disable_rls_temp.sql`) (15m) — confirmar que nunca foram aplicadas em prod
- [ ] **Trocar CORS `*` por whitelist** no MCP HTTP (`atlas-eye-mcp/src/index.ts:52`) (30m)
- [ ] **HMAC no webhook Uazapi** (`supabase/functions/chat-webhook-inbound`) (1h)
- [ ] **Remover `ignoreBuildErrors` e `ignoreDuringBuilds`** do `next.config.ts`, corrigir erros que aparecerem (2h)

---

## 🟠 Janela 1 — 30 dias — ~60h

### Chat — Lead Filter Overhaul (implementado, aguardando QA manual)
- [x] Migration `database/026_lead_search.sql` aplicada em prod Supabase `hklfcfadultzuhwgkqmz` (`pg_trgm`+`unaccent` em `leads` e `lead_activities`).
- [x] RPC `search_leads` deployada e validada: query real `q='alcineia'` retornou 3 leads via `match_type='message'`, confirmando a causa-raiz (nome nunca esteve em `leads.title`, só no histórico).
- [x] Rota `POST /api/leads/search` implementada.
- [x] Hook de busca implementado e `LeadList` ligado ao fluxo híbrido com snippet/highlight.
- [ ] QA manual no navegador: busca por nome, telefone e conteúdo de mensagem; ordenação de pinned; respeito a `view_own_only`; simulação de falha da API para validar fallback client-side.
- Desvios menores do spec (não alteram semântica): adicionada diretiva `#variable_conflict use_column` e `SET search_path = extensions, public` em `norm_text` — ambos necessários para o SQL compilar.
- Spec: `docs/superpowers/specs/2026-04-13-lead-filter-design.md` · Plano: `docs/superpowers/plans/2026-04-13-lead-filter.md`.

### Segurança & guardrails (20h)
- [ ] Migrar todos os secrets para GitHub Secrets + Vercel Env Vars (4h)
- [ ] Refatorar `deploy.mjs` lendo SSH key e token via env (2h)
- [ ] `git-filter-repo` para remover secrets do histórico (2h)
- [ ] Rate limiting em `/api/**` (Upstash ou `@vercel/ratelimit`) (4h)
- [ ] Substituir validação manual por **zod schemas** nas rotas de leads, pipelines, tags, custom-fields, notifications (6h)
- [ ] Idempotency-Key em POST de `/api/leads` e `/api/leads/[id]/messages` (2h)

### CI/CD básico (12h)
- [ ] `.github/workflows/ci.yml`: build + type-check + lint em PRs (3h)
- [ ] `.github/workflows/deploy-vercel.yml`: deploy automático ao merge main (2h)
- [ ] `.github/workflows/deploy-mcp.yml`: SSH deploy via secrets (3h)
- [ ] `.github/workflows/publish-n8n-node.yml`: `npm publish` em tag (2h)
- [ ] Husky + lint-staged pre-commit (2h)

### Limpeza (10h)
- [ ] Executar `CLEANUP_PLAN.md` fases 1-6 (4h)
- [ ] Decidir destino do `trinks-mcp` (completar ou arquivar) (2-6h)
- [ ] Renumerar migrations duplicadas e consolidar cadeia RLS (3h)

### Observabilidade mínima (10h)
- [ ] Sentry no `atlas-eye/` (frontend + API routes) (3h)
- [ ] Sentry nas edge functions (2h)
- [ ] Health check robusto em `atlas-eye-mcp` + cron externo (healthchecks.io) (2h)
- [ ] Logger estruturado (`pino` ou similar) substituindo 26 `console.log` (3h)

### DX (8h)
- [ ] `supabase gen types` + commit em CI (2h)
- [ ] Ambiente staging (clone do Supabase + Vercel preview) (4h)
- [ ] Consolidar docs em `docs/` e atualizar índice (2h)

---

## 🟡 Janela 2 — 30-90 dias — ~120h

### Testes automatizados (50h)
- [ ] Setup Vitest + Testing Library + MSW (4h)
- [ ] Unit tests para hooks críticos (`useLeads`, `usePipeline`, `useAuth`, `useTags`, `useCustomFields`) — alvo 70% (20h)
- [ ] Integration tests para API routes de leads e pipelines (15h)
- [ ] Contract tests para MCP tools (6h)
- [ ] E2E smoke (Playwright): login → create lead → drag stage → tag (5h)

### Refactor de dívida técnica (40h)
- [ ] Quebrar `LeadDetailsSidebar` (758L) em sub-componentes (8h)
- [ ] Quebrar `ActivityTimeline` (704L) (6h)
- [ ] Quebrar `PipelineSettingsPanel` (637L) (6h)
- [ ] Eliminar 80% dos `any` (tipos específicos em catch blocks, error classes) (10h)
- [ ] Error boundaries globais + por-rota (4h)
- [ ] Fix N+1 em `/api/leads` quando `tags_match='all'` (2h)
- [ ] Decidir `title` vs `name` (renomear coluna ou documentar mapping) (4h)

### Integração & DRY (20h)
- [ ] `packages/api-client` compartilhado por MCP, n8n node e trinks-mcp (10h)
- [ ] Zod schemas centrais para Lead/Pipeline/Stage/Tag (6h)
- [ ] `withAuth` HOF eliminando boilerplate nas rotas (4h)

### Ops (10h)
- [ ] Backups Supabase diários + runbook de restore (4h)
- [ ] CHANGELOG + semantic-release nos sub-projetos versionáveis (3h)
- [ ] Dashboards Grafana/Supabase (3h)

---

## 🟢 Janela 3 — 90+ dias — contínuo

### Escalabilidade
- [ ] Versionamento de API (`/api/v1/**`)
- [ ] Circuit breaker nas integrações externas (Uazapi, Anthropic)
- [ ] Consumir Supabase Realtime do MCP (push para AI agents)

### Compliance
- [ ] Auditoria GDPR/LGPD: dados armazenados, retenção, direito ao esquecimento
- [ ] Audit trail completo (quem mudou o quê, quando, via qual cliente)
- [ ] Pentest externo em staging
- [ ] 2FA obrigatório para admins

### Performance
- [ ] Bundle analysis (`@next/bundle-analyzer`)
- [ ] Lazy loading de `@dnd-kit` + `emoji-picker-react`
- [ ] ISR/SWR cache em rotas que permitem

### UX
- [ ] i18n (`next-intl`) — EN/PT
- [ ] Dark mode consistente
- [ ] Acessibilidade (ARIA, keyboard nav)

---

## Métricas de sucesso

| KPI | Baseline hoje | Meta 90d |
|---|---|---|
| Secrets no repo | 8 | 0 |
| Cobertura de testes | 0% | 60% |
| Build com erros mascarados | sim | não |
| Tempo de deploy manual → automático | ~30min | <5min |
| MTTR (incidente) | indefinido | <2h com Sentry |
| Arquivos > 500L | 7 | <3 |
| `any` no código | 241 | <50 |
| Docs dispersas na raiz | 21 MDs | 3 MDs (README, QUICKSTART, CHANGELOG) |
