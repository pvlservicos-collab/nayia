# Atlas Eye — Auditoria Geral

**Data:** 2026-04-13
**Escopo:** todos os sub-projetos em `atlasEye/`
**Método:** 8 agentes paralelos de análise estática (stack, segurança, integração, infra, qualidade, estrutura).

---

## Sumário executivo

Atlas Eye é um CRM multi-tenant em produção composto por 6 módulos interdependentes. A **funcionalidade de negócio está sólida** (MVP rodando, 20 rotas REST, 33 MCP tools, nó n8n publicado no npm, 25 tabelas Postgres com RLS). A **saúde operacional é frágil**: secrets expostos, ausência de CI/CD, zero testes automatizados, documentação dispersa e ~50 arquivos de lixo na raiz.

**Score agregado:** 5.2/10 — funcional mas com dívida crítica.

| Dimensão | Score | Nota |
|---|---|---|
| Arquitetura | 8/10 | Boa separação, multi-tenant by design |
| Funcionalidade | 8/10 | MVP completo em produção |
| Segurança | 2/10 | **Secrets vazando, webhooks sem HMAC, CORS `*`** |
| Confiabilidade | 5/10 | Deploy manual, sem rollback |
| Observabilidade | 2/10 | Sem Sentry/APM, logs não-estruturados |
| Testes | 0/10 | 0 suites automatizadas |
| Documentação | 6/10 | Ampla mas dispersa (21 MDs na raiz) |
| Developer Experience | 6/10 | Setup OK, mas build ignora erros |

---

## Inventário de sub-projetos

| Módulo | Stack | Versão | Estado | Obs |
|---|---|---|---|---|
| `atlas-eye/` | Next.js 15 + React 19 + Supabase | 0.1.0 | 🟢 Ativo | App principal (20 rotas API, 17 hooks, 0 tests) |
| `atlas-eye-mcp/` | TS + @modelcontextprotocol/sdk 1.12 | 1.1.0 | 🟢 Prod | 33 tools, deploy via SSH em `72.61.216.19:3100` |
| `trinks-mcp/` | TS + @modelcontextprotocol/sdk 1.12 | 1.0.0 | 🔴 Quebrado | Falta `src/index.ts` — não compila |
| `n8n-nodes-atlaseye/` | TS + n8n-workflow | 2.1.1 | 🟢 Publicado | npm community node, 5 resources / 30+ ops |
| `supabase/functions/` | Deno TS | — | 🟢 Prod | 7 edge functions (webhook, invites, IA) |
| `database/` | PostgreSQL + RLS | — | 🟠 Confuso | 25 migrations, várias duplicatas numéricas e debug |
| `frontend/` | HTML estático (Stitch) | — | 🔴 Legado | 3 mockups, substituído pelo `atlas-eye/` |

---

## 1. Problemas críticos (agir em 24h)

| # | Categoria | Local | Descrição |
|---|---|---|---|
| 1 | Secret | `atlas-eye-mcp/deploy.mjs:13` | SSH root password em plaintext: `@Tlassolutions321` |
| 2 | Secret | `atlas-eye-mcp/deploy.mjs:121` | API token real: `atl_d68e719e24dc...` |
| 3 | Secret | `.env.local:4` + `atlas-eye/.vercel/.env.production.local` | Supabase **service_role_key** exposto (bypass de RLS) |
| 4 | Secret | `.env.local:8` | UAZAPI admin token |
| 5 | Secret | `n8n-nodes-atlaseye/.npmrc` | Token de publish npm |
| 6 | Secret | `deploy_functions.js` + `apply_006.js` | Supabase personal access token `sbp_ae0aa149...` |
| 7 | DB | `database/018_test_bypass_rls.sql` | Migration de teste desabilita RLS (`USING (true)`) — se aplicada, banco abre |
| 8 | DB | `database/022_disable_rls_temp.sql` | Migration que desliga RLS completamente |
| 9 | CORS | `atlas-eye-mcp/src/index.ts:52` | `Access-Control-Allow-Origin: *` — qualquer origem invoca tools MCP |
| 10 | Webhook | `supabase/functions/chat-webhook-inbound/index.ts` | Webhook Uazapi sem validação de assinatura HMAC |
| 11 | Build | `atlas-eye/next.config.ts:4-9` | `ignoreBuildErrors: true` + `ignoreDuringBuilds: true` — erros de TS/lint mascarados em produção |
| 12 | Trinks MCP | `trinks-mcp/src/` | Falta `index.ts`. `package.json` aponta para `dist/index.js` inexistente |

---

## 2. Problemas altos (2 semanas)

### 2.1 Inconsistências de integração
- **Campo `name` vs `title`**: DB usa `title`, API mapeia para `name`, MCP e n8n esperam `name`. Fonte de bugs silenciosos.
- **Campo `source` não injetado**: n8n node exige `source` no payload mas não injeta automaticamente — auditoria quebrada.
- **3 HTTP clients duplicados** (`atlas-eye-mcp/src/http-client.ts`, `trinks-mcp/src/http-client.ts`, `n8n-nodes-atlaseye/nodes/AtlasEye/transport.ts`).
- **Trinks usa IDs numéricos, Atlas Eye usa UUIDs** — incompatíveis caso integrem.

### 2.2 Falta de guardrails na API
- **Sem rate limiting** em nenhuma rota.
- **Validação de input manual** (regex + `parseInt`), nenhum zod/yup no `atlas-eye/src/app/api/**`.
- `getAll('tags')` aceita arrays ilimitados → DoS via payload grande.
- **Sem idempotency keys** — retries criam leads duplicados.

### 2.3 Dívida técnica concentrada em 7 arquivos
- `LeadDetailsSidebar.tsx` (758 linhas)
- `ActivityTimeline.tsx` (704 linhas)
- `PipelineSettingsPanel.tsx` (637 linhas)
- `whatsapp-lite/page.tsx` (595)
- `organization/page.tsx` (570)
- `workspaces/page.tsx` (542)
- `api/docs/route.ts` (526)

### 2.4 Tipagem
- **241 usos de `any`** (majoria em `catch (err: any)`).
- **Types Supabase não são gerados** (`supabase gen types` ausente).
- Zod só existe no `atlas-eye-mcp` — não há single source of truth.

### 2.5 Migrations confusas
- Números duplicados: 004, 005, 007, 009, 010 têm duas migrations cada.
- Cadeia de 6 migrations corrigindo o mesmo bug RLS (015→021).
- 2 migrations de teste no meio do histórico (018, 022).

---

## 3. Problemas médios

- **26 console.log/error em produção** (principalmente `whatsapp-lite/page.tsx`, `chat/page.tsx`, APIs `/users`, `/admin/*`).
- **0 testes automatizados** em todos os sub-projetos.
- **0 error boundaries** no React — crash de componente derruba UI.
- **Realtime do Supabase configurado mas não consumido** por nenhum cliente.
- **Sem ambientes separados**: dev/staging/prod compartilham a mesma instância Supabase.
- **Sem CI/CD** (nenhum `.github/workflows`, nenhum husky).
- **Sem backups documentados** e sem runbook de restore.
- **Múltiplas stored procedures** com `SECURITY DEFINER` — auditar se todas checam `has_permission()`.
- **N+1 query** em `/api/leads` quando `tags_match='all'` — loop de 1 query por tag.
- **Versões divergentes**: root 0.1.0, mcp 1.1.0, n8n 2.1.1 — sem CHANGELOG.

---

## 4. Lixo identificado

### 4.1 Deletar
- `stitch_chat1_*.json`, `stitch_chat2_*.json`, `stitch_pipeline_*.json`, `stitch_tools_full.json` (~120KB)
- `stitch_edit_screens_fixed.js`, `stitch_pipeline_edit.js`
- `check_advisors.js` + `check_advisors2.js` + `check_advisors3.js` (3 quase-duplicatas)
- `database/018_test_bypass_rls.sql` (PERIGO)
- `database/022_disable_rls_temp.sql` (PERIGO)
- `Planning/`, `UI-UX Improvements/` (diretórios vazios)
- `scripts/check-todabella.ts`, `scripts/fix-lead-names.ts` (one-offs executados)
- `scripts/sync-avatars.mjs` OU `scripts/sync-avatars.ts` (duplicatas)

### 4.2 Arquivar em `docs/archive/`
- `SETUP_PROGRESS.md`, `STATUS.md`, `DELIVERY_SUMMARY.md`, `IMPLEMENTATION_COMPLETE.md`, `STITCH_COMPLETION_REPORT.md`
- `findings.md`, `progress.md`, `task_plan.md`
- `temp_old/` (build antigo do n8n node)
- `frontend/` (mockups Stitch substituídos pelo `atlas-eye/`)

### 4.3 Consolidar
- `ACESSO_RAPIDO.md` → mesclar em `README.md` + `QUICKSTART.md`
- `PORTA_ATUALIZADA.md` → 1 parágrafo em README
- `crm_functions.md` → mesclar em `schema.md`
- Migrations RLS 015→022 → uma única `fix_rls_final.sql` + arquivar as anteriores

---

## 5. Top 10 ações priorizadas

1. **Rotacionar TODOS os tokens hoje** (Supabase service_role, anon, UAZAPI admin, API token `atl_*`, SSH password, npm token, Supabase PAT).
2. **Adicionar ao `.gitignore`**: `.vercel/`, `deploy.mjs`, `apply_*.js`, `deploy_functions.js`, `.npmrc`, `.env*`.
3. **Deletar migrations 018 e 022** (bypass RLS) do diretório e histórico.
4. **Remover `ignoreBuildErrors` e `ignoreDuringBuilds`** do `next.config.ts` e corrigir erros resultantes.
5. **Trocar CORS `*` por whitelist** no MCP HTTP server.
6. **Validar webhook Uazapi** com HMAC-SHA256 em `chat-webhook-inbound`.
7. **Criar `trinks-mcp/src/index.ts`** seguindo padrão do `atlas-eye-mcp` (ou arquivar o projeto).
8. **Consolidar cliente HTTP** em `packages/api-client` compartilhado pelos 3 consumidores.
9. **Setup CI/CD GitHub Actions**: build + type-check + lint em PRs; deploy automático ao merge.
10. **Adicionar Sentry + rate limiting** (Upstash ou Vercel) nas API routes.

---

## 6. Relatórios detalhados

Esta auditoria condensa 8 relatórios por domínio. Para o detalhe completo com `arquivo:linha` de cada achado, veja os documentos irmãos nesta pasta:

- `PROJECT_STATUS.md` — snapshot módulo por módulo
- `SECURITY.md` — checklist de remediação de segurança
- `ARCHITECTURE.md` — mapa de integração end-to-end
- `CLEANUP_PLAN.md` — script de limpeza da raiz
- `ROADMAP.md` — plano 0-30 / 30-90 / 90+ dias
