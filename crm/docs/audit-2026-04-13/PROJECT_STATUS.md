# Atlas Eye — Estágio Atual

**Snapshot em 2026-04-13.** Um módulo por seção.

---

## atlas-eye/ — App principal (Next.js 15)

**Versão:** 0.1.0 (ainda 0.x apesar de estar em produção)
**Stack:** Next.js 15.0 (App Router) · React 19 · TypeScript 5.3 (strict) · Supabase 2.45 · Tailwind 3.4
**Entrypoint:** `src/app/`

### O que já funciona
- **Auth** via Supabase (JWT + API tokens `atl_*`)
- **Pipeline Kanban** com drag-drop, realtime sync, optimistic updates
- **Chat** estilo WhatsApp com timeline, notas, áudio
- **20 rotas REST** cobrindo leads/pipelines/stages/tags/users/custom-fields/notifications
- **Admin panel** (`/api/admin/{create,delete}-workspace`)
- **Settings completo**: pipelines, custom fields, members, tags, integrations, organization profile
- **Supabase Realtime** ligado (leads + mensagens)
- **OpenAPI docs** em `/api/docs` (Scalar)

### Dívida mais visível
- `next.config.ts` → `ignoreBuildErrors: true` + `ignoreDuringBuilds: true` (🔴 remover)
- **Zero testes** (`package.json` não tem `test` script)
- **7 arquivos > 500 linhas** (ver AUDIT_REPORT §2.3)
- **241 `any`** espalhados
- **26 console.log em produção** (em `whatsapp-lite/page.tsx`, `chat/page.tsx`, APIs admin)
- **0 error boundaries**
- Hook `useLeads.ts:59-82` tem fallback silencioso quando JOIN falha — sintoma de query instável

### Escopo pendente
- Testes automatizados (nunca existiram)
- i18n (strings hardcoded em PT-BR)
- Rate limiting em `/api/**`
- Input validation com zod em `/api/**`
- **Lead Filter Overhaul** — implementação completa em 2026-04-13, aguardando QA manual no navegador antes do flag final de shipped. Substitui o filtro client-only de `LeadList.tsx:182` por busca híbrida (RPC `search_leads` + `POST /api/leads/search`, indexes `pg_trgm`/`unaccent` em `leads` e `lead_activities`). Migration `database/026_lead_search.sql` aplicada em prod Supabase `hklfcfadultzuhwgkqmz`; 13/13 smoke tests backend passam (`scripts/smoke-026.mjs`); 7 arquivos de frontend alterados, type-check limpo. Spec: `docs/superpowers/specs/2026-04-13-lead-filter-design.md` · Plano: `docs/superpowers/plans/2026-04-13-lead-filter.md`.

---

## atlas-eye-mcp/ — MCP Server (production)

**Versão:** 1.1.0
**Deploy:** VPS `72.61.216.19:3100` via PM2, rodando `dist/index.js --http`
**SDK:** `@modelcontextprotocol/sdk@1.12.1`
**Transporte:** stdio (padrão) + HTTP streamable (`--http`)

### 33 tools expostas
- **Leads (11):** list, get, create, update, delete, get_history, list_messages, add_history_event, send_message, edit_history_event, delete_history_event
- **Pipelines (11):** CRUD pipelines + CRUD stages + `get_stage_colors`
- **Users (3):** list, invite, remove
- **Tags (2):** list, create
- **Custom fields (2):** list, get
- **Notifications (1):** send (broadcast se `recipient_member_id` omitido)
- **Admin (2):** create_workspace, delete_workspace (requerem JWT superadmin — sem validação no cliente)
- **Auth (1):** setup_owner (IRREVERSÍVEL)

### Pontos fracos
- `deploy.mjs` com SSH password + API token hardcoded (🔴 rotacionar)
- **CORS `*`** no servidor HTTP
- **Sem try/catch** dentro das tools — erro de API vaza raw
- `send_notification` sem `recipient_member_id` faz broadcast global silencioso
- Sem logging estruturado, sem health check robusto
- **Zero testes**

---

## trinks-mcp/ — MCP Server (quebrado)

**Versão:** 1.0.0
**Status:** 🔴 **Não compila**. `package.json` aponta para `dist/index.js` mas falta `src/index.ts`.

### 21 tools planejadas (não expostas)
- **Agendamentos (10):** listar/buscar/criar/atualizar + status (confirmar, cancelar, finalizar, faltou, em_atendimento) + agenda_profissionais
- **Clientes (11):** CRUD + crédito + vale-presente + etiquetas + telefones

### Dívida
- **Falta `index.ts` de registro** — precisa ser criado copiando padrão do atlas-eye-mcp
- **Sem `.env.example`** (requer `TRINKS_API_KEY` + `TRINKS_ESTABELECIMENTO_ID`)
- IDs numéricos (int) incompatíveis com UUIDs do Atlas Eye — sem bridge entre os dois domínios
- Status HTTP via endpoints separados (`/agendamentos/{id}/status/confirmado` etc) em vez de PATCH único

### Decisão pendente
Arquivar ou completar? Se usar internamente no Atlas Solutions (salões), completar; senão, mover para `docs/archive/`.

---

## n8n-nodes-atlaseye/ — Community node (npm)

**Versão:** 2.1.1 (publicado no npm)
**Stack:** TS 5.4 · n8n-workflow (peerDep) · Gulp para assets

### 5 resources expostos
- **Lead (11 ops):** CRUD + sendMessage + listMessages + getHistory + addEvent + editEvent + deleteEvent
- **Pipeline (10 ops):** CRUD funil + CRUD stages + listColors
- **Tag (2 ops):** create, list (falta update)
- **User (3 ops):** get, list, invite/remove/update
- **Notification (3 ops):** send, list, markRead

### Pontos positivos
- TS strict
- Sem console.log
- 13 mensagens de erro customizadas em PT-BR
- Credential type `atlasEyeApi` com test endpoint
- `loadOptions` dinâmico para dropdowns (pipelines, tags, users)

### Pontos fracos
- `.npmrc` com token npm commitado (🔴 rotacionar)
- **Não injeta `source` automaticamente** em mutations — auditoria quebrada
- Sem testes automatizados (só 2 arquivos `test-*.mjs` manuais)
- Publish sem CI — manual via `npm publish`

---

## supabase/ — Edge Functions + Config

**Plataforma:** Supabase Cloud · Projeto `hklfcfadultzuhwgkqmz`

### 7 edge functions em produção
| Function | Função | Auth |
|---|---|---|
| `accept-invite` | Aceita convite e ativa member | token |
| `chat-send-message` | Envia msg via integração | Bearer |
| `chat-webhook-inbound` | Recebe webhook Uazapi (WhatsApp) | **🔴 nenhuma** |
| `fetch-avatar` | Baixa avatar e armazena no Storage | Bearer |
| `generate-ai-insights` | Claude Haiku → insights IA no lead | Bearer |
| `invite-member` | Manda magic link + cria member | Bearer |
| `manage-member` | Update/remove member com RBAC | Bearer |

### Dívida
- **Webhook inbound sem HMAC signature** (qualquer um pode disparar)
- **2 TODOs críticos** em `chat-send-message` (integração Z-API / Evolution inacabada)
- Deploy manual via `deploy_functions.js` com PAT Supabase hardcoded

---

## database/ — PostgreSQL Schema

### Modelo (25 tabelas)
**Tenancy:** `tiers`, `organizations`
**Usuários/RBAC:** `profiles`, `organization_roles`, `organization_members`
**CRM core:** `pipelines`, `pipeline_stages`, `leads`, `lead_stage_history`, `lead_activities`
**IA:** `lead_ai_insights`
**Integrações:** `integrations`
**Custom fields:** `custom_field_definitions`, `custom_field_index_values`
**Tags:** `tags`, `lead_tags`
**UX:** `ui_state_drafts`
**Segurança/Auditoria:** `audit_logs`, `notifications`, `user_notification_settings`, `automation_settings`

**Padrão multi-tenant:** PK composta `(organization_id, id)` em quase todas; FKs também compostas. RLS em 100% das tabelas via função `is_org_member(org_id)`.

### 4 RPCs em produção
- `delete_pipeline_stage(stage_id, org_id, fallback_stage_id)`
- `reorder_pipeline_stages(pipeline_id, org_id, stage_ranks jsonb)`
- `remove_member(member_id, org_id)`
- `delete_custom_field(field_id, org_id)`

Todas com `SECURITY DEFINER` + `SET search_path = ''`.

### Dívida
- **Números duplicados**: 004, 005, 007, 009, 010 têm 2 migrations cada
- **Cadeia de 6 fixes RLS** (015→021) sobre o mesmo bug
- **Migrations de teste no histórico** (018, 022) que desligam RLS
- **`database/` vs `supabase/migrations/`** — source of truth ambíguo
- **Sem tipos gerados** (`supabase gen types` não rodou)

---

## Infra & Operações

| Item | Estado |
|---|---|
| Deploy atlas-eye | Vercel (presumido, sem `vercel.json`) |
| Deploy atlas-eye-mcp | SSH manual via `deploy.mjs` (PM2 no VPS) |
| Deploy trinks-mcp | Não existe |
| Deploy n8n-node | `npm publish` manual |
| Deploy edge functions | `deploy_functions.js` manual |
| Deploy migrations | `apply_006.js` ad-hoc |
| Ambientes | 🔴 Apenas 1 (dev=prod) |
| Secrets manager | 🔴 `.env` commitados |
| CI/CD | 🔴 Não existe |
| Error tracking | 🔴 Não existe |
| APM/metrics | 🔴 Não existe |
| Backup | 🟡 Depende do padrão Supabase (não documentado) |
| Health check | 🟡 Manual (`curl /health` do MCP) |

---

## Documentação existente na raiz

**21 arquivos .md** — muitos redundantes ou históricos. Plano de consolidação em `CLEANUP_PLAN.md`.

Core a manter: `README.md`, `QUICKSTART.md`, `DOCUMENTATION_INDEX.md`, `API_REFERENCE.md`, `ARQUITECTURA_TECNICA.md`, `schema.md`, `IMPLEMENTATION_GUIDE.md`, `N8N_NODE.md`, `SETUP.md`, `TESTING_GUIDE.md`.

Arquivar: `SETUP_PROGRESS.md`, `STATUS.md`, `DELIVERY_SUMMARY.md`, `IMPLEMENTATION_COMPLETE.md`, `STITCH_COMPLETION_REPORT.md`, `findings.md`, `progress.md`, `task_plan.md`, `PORTA_ATUALIZADA.md`, `ACESSO_RAPIDO.md`.
