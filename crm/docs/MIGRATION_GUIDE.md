# 🔄 Guia de Migração: Supabase → Vercel (Neon + Blob + NextAuth)

## O que mudou

| Antes (Supabase) | Depois (Vercel) |
|---|---|
| Supabase PostgreSQL | **Neon** (Postgres serverless) |
| Supabase Storage (avatars, org-logos) | **Vercel Blob** |
| Supabase Auth (JWT, sessões) | **NextAuth v5** (Credentials) |
| Supabase Realtime (WebSockets) | **Pusher** (WebSockets gerenciado) |
| Supabase Edge Functions | **Next.js API Routes** (serverless) |
| Supabase Vault (secrets) | Tabela `integration_secrets` no Neon |
| RLS (Row Level Security) | Filtros `organization_id` no Drizzle |

---

## Passo a Passo para Colocar no Ar

### 1. Criar o banco Neon

**Opção A — Via Vercel (recomendado):**
1. Abra vercel.com → seu projeto → aba **Storage**
2. Clique em **Create Database → Neon**
3. A `DATABASE_URL` é adicionada automaticamente às env vars do Vercel

**Opção B — Neon direto:**
1. Acesse console.neon.tech → Create Project
2. Copie a **Connection String** (formato `postgresql://...`)
3. Adicione como `DATABASE_URL` no Vercel

**Executar a migração SQL:**
1. No painel Neon → **SQL Editor**
2. Cole o conteúdo de `database/neon_migration.sql`
3. Execute (cria todas as tabelas, índices e funções)

---

### 2. Criar o Vercel Blob Store

1. vercel.com → Storage → **Create Store → Blob**
2. Nome sugerido: `atlas-eye-uploads`
3. O token `BLOB_READ_WRITE_TOKEN` é adicionado automaticamente

---

### 3. Configurar Pusher (Realtime)

1. Acesse pusher.com → **Create App**
2. Copie as credenciais para o `.env.local`:
   ```
   PUSHER_APP_ID=...
   PUSHER_KEY=...
   PUSHER_SECRET=...
   PUSHER_CLUSTER=us2
   NEXT_PUBLIC_PUSHER_KEY=...
   NEXT_PUBLIC_PUSHER_CLUSTER=us2
   ```
3. No Vercel, adicione as mesmas vars em **Settings → Environment Variables**

---

### 4. Configurar variáveis de ambiente

Copie `.env.local.example` para `.env.local` e preencha todos os valores.

No Vercel (Settings → Environment Variables), adicione:
- `DATABASE_URL` (automático se usou integração Neon)
- `BLOB_READ_WRITE_TOKEN` (automático se usou integração Blob)
- `AUTH_SECRET` → gere com: `openssl rand -base64 32`
- `NEXTAUTH_URL` → `https://seu-app.vercel.app`
- `PUSHER_APP_ID`, `PUSHER_KEY`, `PUSHER_SECRET`, `PUSHER_CLUSTER`
- `NEXT_PUBLIC_PUSHER_KEY`, `NEXT_PUBLIC_PUSHER_CLUSTER`
- `FACEBOOK_WEBHOOK_VERIFY_TOKEN`
- `UAZAPI_SERVER_URL`, `UAZAPI_ADMIN_TOKEN` (se usar WhatsApp Lite)

---

### 5. Criar o primeiro usuário admin

Após o deploy, chame a API para criar o workspace inicial:

```bash
# 1. Criar workspace (requer um usuário superadmin já existente)
# OU use o script abaixo para criar o primeiro usuário diretamente no banco

# No SQL Editor do Neon — substitua os valores:
INSERT INTO users (email, password_hash)
VALUES ('seu@email.com', '$2a$12$HASH_GERADO_POR_BCRYPT');

INSERT INTO profiles (id, full_name, is_superadmin)
SELECT id, 'Seu Nome', true FROM users WHERE email = 'seu@email.com';
```

Para gerar o hash da senha (execute localmente):
```bash
node -e "const b = require('bcryptjs'); b.hash('sua_senha', 12).then(console.log)"
```

---

### 6. Deploy

```bash
# Instalar dependências novas
npm install

# Verificar build local
npm run build

# Deploy
git add .
git commit -m "feat: migração Supabase → Neon + Vercel Blob + NextAuth"
git push origin main
# Vercel faz deploy automático
```

---

## Arquivos que ainda precisam de atenção manual

Os hooks abaixo ainda têm chamadas `supabase.from()` que precisam ser
migradas para `fetch('/api/...')`. Eles mostrarão um erro claro no console
apontando exatamente onde está a chamada pendente:

- `src/hooks/usePipeline.ts` — migrar para `fetch('/api/pipelines')`
- `src/hooks/useTags.ts` — migrar para `fetch('/api/tags')`
- `src/hooks/useCustomFields.ts` — migrar para `fetch('/api/custom-fields')`
- `src/hooks/useOrganizationMembers.ts` — migrar para `fetch('/api/users')`
- `src/hooks/useNotifications.ts` — migrar para `fetch('/api/notifications')`
- `src/hooks/useIntegrations.ts` — migrar para `fetch('/api/integrations')`
- `src/components/Settings/MembersPanel.tsx` — migrar para `fetch('/api/users')`
- `src/components/Settings/MemberModal.tsx` — migrar para `fetch('/api/users')`

### Padrão de migração para cada hook:

```typescript
// ANTES (supabase client direto)
const { data } = await supabase.from('tags').select('*').eq('organization_id', orgId)

// DEPOIS (fetch para API route)
const res = await fetch('/api/tags')
const { data } = await res.json()
```

---

## Edge Functions do Supabase

As Edge Functions (`supabase/functions/`) **não são migradas automaticamente**.
Elas precisam ser convertidas para **Next.js API Routes**.

| Edge Function | Equivalente Next.js |
|---|---|
| `chat-webhook-inbound` | `/api/webhooks/whatsapp` (a criar) |
| `chat-send-message` | Já existe em `/api/leads/[id]/messages` |
| `fetch-avatar` | `/api/leads/[id]/avatar` (a criar) |
| `invite-member` | Integrar com `/api/users` |
| `manage-member` | `/api/users/[member_id]` |
| `accept-invite` | `/api/auth/accept-invite` (a criar) |
| `generate-ai-insights` | `/api/leads/[id]/ai-insights` (a criar) |
| `follow-up-worker` | Vercel Cron Job (a criar) |

---

## Estrutura de arquivos novos

```
src/lib/
  db.ts          ← cliente Neon/Drizzle (substitui @supabase/supabase-js server)
  schema.ts      ← definição de todas as tabelas com Drizzle ORM
  auth.ts        ← NextAuth v5 config (substitui Supabase Auth)
  auth-helpers.ts← helpers client-side (substitui supabase.auth.*)
  blob.ts        ← Vercel Blob (substitui supabase.storage.*)
  realtime.ts    ← Pusher server-side (substitui supabase.channel())
  db-helpers.ts  ← queries Drizzle reutilizáveis

src/hooks/
  usePusher.ts   ← hook client-side Pusher (substitui supabase.channel())

src/app/api/
  upload/        ← substitui supabase.storage.from().upload()
  workspaces/    ← lista orgs do usuário logado
  auth/[...nextauth]/ ← handler NextAuth
  webhooks/facebook/  ← webhook API Oficial Facebook/WhatsApp

database/
  neon_migration.sql  ← SQL completo para rodar no Neon
```
