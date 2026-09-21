# Atlas Eye CRM — Guia de Implementação Completo

**Data:** 2026-03-12
**Versão:** 2.0
**Status:** ✅ Front e Back Integralmente Conectados + N8n Node Live

---

## 📑 Índice

1. [Visão Geral](#visão-geral)
2. [Arquitetura Atualizada](#arquitetura-atualizada)
3. [Componentes e Páginas](#componentes-e-páginas)
4. [Ecosistema de Hooks (Data Layer)](#ecosistema-de-hooks)
5. [Segurança e Variáveis de Ambiente](#segurança-e-env)
6. [Integração N8n](#integração-n8n)
7. [Deployment](#deployment)

---

## 🎯 Visão Geral

O Atlas Eye CRM superou a fase inicial de "telas geradas" pelo Stitch e agora é um SPA Next.js multi-tenant robusto acoplado ao Supabase (Postgres, RLS, Edge Functions, Realtime, Storage).

### Stack Tecnológico

| Camada | Tecnologia Principal |
|--------|----------------------|
| **Frontend** | React 19 + Next.js 15 (App Router) |
| **Styling** | Tailwind CSS + Variáveis customizadas |
| **Database** | PostgreSQL (25 tabelas, RLS integral no tenant) |
| **Backend/Auth** | Supabase Auth + Edge Functions via Deno |
| **APIs** | 20 Endpoints REST nativos no Next.js (`/api/*`) |
| **Automação** | `n8n-nodes-atlaseye` (Custom Community Node) |

---

## 🏗️ Arquitetura Atualizada

### Fluxo de Dados Cliente-Servidor

O sistema não usa queries locais em componentes diretamente (para evitar boilerplate e garantir refetch). Existe uma camada de abstração forte em **Hooks customizados** que utilizam o Supabase client pre-configurado (`@/lib/supabase`).

1. **Pages** chamam **Components** (`src/app/`)
2. **Components** se inscrevem em **Hooks** (`src/hooks/`)
3. **Hooks** gerenciam `useState`, `useEffect` e o **Supabase Realtime Channel**.
4. Disparos de escrita ou webhook são feitos enviando pra `api_tokens` / `/api/`.

---

## ⚛️ Componentes e Páginas

A UI evoluiu de 3 telas estáticas para **19 Rotas** dinâmicas no App Router (`src/app/`):

### Estrutura de Rotas

```text
app/
├── (authenticated)/
│   ├── page.tsx (Dashboard Geral)
│   ├── pipeline/page.tsx (Kanban Avançado com Drag-and-Drop)
│   ├── chat/page.tsx (Caixa de Entrada / Chat Unificado)
│   ├── notifications/page.tsx (Central de Notificações)
│   └── settings/
│       ├── page.tsx (Overview do Workspace)
│       ├── profile/page.tsx
│       ├── organization/page.tsx
│       ├── members/page.tsx (Convites/RBAC)
│       ├── custom-fields/page.tsx (Criador de formulários)
│       ├── tags/page.tsx
│       ├── pipelines/page.tsx
│       ├── notifications/page.tsx
│       └── integrations/
│           ├── whatsapp-api/
│           ├── whatsapp-cloud-api/
│           └── whatsapp-lite/ (QR Code via API)
├── login/page.tsx (Autenticação + Roteamento por Tenant)
├── welcome/page.tsx (Landing do Setup Inicial Mágico)
└── workspaces/page.tsx (Multitenant Selector no Login Multi-Org)
```

### Componentes Críticos

- **PipelineBoard**: Agora com suporte a *Custom Fields* no card frontal via metadados opcionais e *goals* por estágio.
- **ChatWindow**: Suporte a envio de e-mails, templates, notas internas, timeline multicanal mesclada automaticamente (via Supabase Edge Functions).
- **SettingsAccessGuard**: Componente HOC novo que injeta bloqueio se o role actual (member/admin) não puder ver as tabs de setting da Organização.

---

## 🪝 Ecosistema de Hooks (Data Layer)

Para consumir dados sem precisar fazer queries no Supabase dentro do JSX, temos **17 Hooks dedicados**:

1. **Autenticação e Membros**
   - `useAuth`: Traz o perfil logado e injeta contexto `organizationId`.
   - `useOrganizationMembers`: Lista toda a equipe ativa para selects de `owner` e @menções.

2. **Core CRM (Kanban & Leads)**
   - `usePipelines`: Listagem de funis.
   - `useLeads`: Consulta massiva otimizada de Leads, injetando Tags nativamente.
   - `useLeadPipelineStages`: Carregamento do contexto específico de board atual (Cores, Goals).

3. **Caixa de Entrada / Histórico**
   - `useLeadActivities`: A linha do tempo granular de um Lead (Mensagens, Notas).
   - `useLeadHistory`: Transições do kanban (ex: "Helen moveu para Negociação às 14h").
   - `useTimeline`: Timeline unificada (atividades + mudança de cor/estágio).

4. **Metadados / Roteamento**
   - `useTags`: Tags da Org (Cores HEX em string, sem limitações).
   - `useCustomFields`: Resgata dinamicamente formulários definidos no Settings -> Custom Fields (Type: select, text, datetime...).

5. **Avisos do Sistema**
   - `useNotifications`: O sino da barra superior que faz sync realtime com o canal `notifications` de `recipient_id`.
   - `useApiNotifications`: Carrega rules automatizadas habilitadas.

---

## 🔒 Segurança e Variáveis de Ambiente (ENVs)

Toda conexão depende das ENVs abaixo.

> ⚠️ [CRÍTICO] **Nuca insira as chaves hardcoded nos seus arquivos ou no código enviado ao GitHub.**

Crie um arquivo `.env.local`:

```bash
# Frontend Next.js / Supabase Client
NEXT_PUBLIC_SUPABASE_URL=https://<id-do-projeto>.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...

# Segurança de API (Nunca expor ao cliente - usado apenas por Edge Functions ou Scripts DB)
SUPABASE_SERVICE_ROLE_KEY=eyJ...
```

*Nota para MCP Servers*: No seu `claude_desktop_config.json` ou `mcp.json`, quando for conectar Database de fato com Supabase MCP, forneça a role `SUPABASE_ACCESS_TOKEN`. Nunca use chaves publicáveis no lugar de `ACCESS_TOKEN`.

As **APIs Locais** que acessam `createSupabaseAdmin()` utilizam o Service Role sob o proxy para realizar requisições de admin, bypassando RLS e confiando apenas no JWT que foi traduzido em `auth.organizationId` ou em um Token `atl_` nativo gerado pelo sistema.

---

## 🤖 Integração N8n (Atlas Eye Node)

Dada a natureza aberta do CRM, criamos um [Community Node (`n8n-nodes-atlaseye`)](https://www.npmjs.com/package/n8n-nodes-atlaseye) oficial (v1.2.8).

Para testar suas apis nele:
1. Vá em `Settings > Perfil / Integrações` (Seu Frontend Atlas Eye)
2. Gere um Token de API (`atl_...`)
3. Use esta chave direto no **Credential Manager** do N8n.
4. Qualquer webhook originado pelo nó consumirá suas `API Routes`, identificando a org corretamente sem login humano.

Consulte o documento `N8N_NODE.md` (no raiz) para arquitetura de triggers e actions completas.

---

## 🚀 Deployment (Vercel Oficial)

O backend do DB está gerido nas nuvens Supabase e a API reside em Serverless Functions e Next.js Route Handlers.

**Frontend Delivery Automático**
- O repositório está linkado à plataforma Vercel.
- O branch `main` ativa builds assim que recebe push.

**Edge Functions**
Se modificar uma pasta de Edge Function (ex: `supabase/functions/chat-webhook-inbound`), é necessário realizar push para o Supabase:
```cmd
npx supabase functions deploy chat-webhook-inbound --project-ref hklfcfadultzuhwg... --no-verify-jwt
```
*(Nota: Para webhooks do WhatsApp que não contém JWT, anote `--no-verify-jwt`)*
