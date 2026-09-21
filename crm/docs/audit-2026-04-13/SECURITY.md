# Atlas Eye — Segurança

**Data:** 2026-04-13
**Classificação:** 🔴 **RISCO CRÍTICO** — rotacionar credenciais hoje.

---

## Inventário de secrets expostos

Todos os valores abaixo estão **em arquivos versionados no workspace** e devem ser tratados como comprometidos.

| # | Tipo | Caminho | Valor (redigido) | Ação |
|---|---|---|---|---|
| 1 | SSH root password | `atlas-eye-mcp/deploy.mjs:13` | `@Tlassolutions321` para `72.61.216.19` | Trocar senha do root, habilitar SSH key-only |
| 2 | Atlas Eye API token | `atlas-eye-mcp/deploy.mjs:121` | `atl_d68e719e24dc...` | Revogar no painel de tokens do Atlas Eye |
| 3 | Supabase `service_role_key` | `.env.local:4` e `atlas-eye/.vercel/.env.production.local` | JWT `eyJhbG...` com role=service_role, exp=2086 | Regenerar em Supabase → Settings → API |
| 4 | Supabase `anon_key` | mesmos arquivos | JWT `eyJhbG...` role=anon | Regenerar (menos crítico mas still expõe org) |
| 5 | UAZAPI admin token | `.env.local:8` | `XQJ9Wpy51CY2vuEB...` | Regenerar em atlas-solutions.uazapi.com |
| 6 | npm auth token | `n8n-nodes-atlaseye/.npmrc` | `npm_soNFO3xJxLnV...` | Revogar em npmjs.org → Account → Tokens |
| 7 | Supabase PAT | `deploy_functions.js` + `apply_006.js` | `sbp_ae0aa149d88f...` | Revogar em Supabase → Account → Access Tokens |
| 8 | Vercel OIDC | `atlas-eye/.vercel/.env.production.local:25` | JWT de deploy | Rotacionar via Vercel CLI `vercel env rm` |

### Processo de rotação recomendado

```bash
# 1. Confirmar que o .gitignore cobre todos os arquivos sensíveis
cat >> .gitignore <<'EOF'
.env
.env.local
.env.production
.env.production.local
.vercel/
**/.vercel/
.npmrc
deploy.mjs
deploy_functions.js
apply_*.js
scripts/sync-*.mjs
EOF

# 2. Remover do tracking (mantém no disco)
git rm --cached .env.local atlas-eye/.vercel/.env.production.local \
  atlas-eye-mcp/deploy.mjs n8n-nodes-atlaseye/.npmrc \
  deploy_functions.js apply_006.js

# 3. Limpar histórico (equipe precisa re-clonar após)
git filter-repo --path .env.local --path atlas-eye/.vercel/ \
  --path atlas-eye-mcp/deploy.mjs --path n8n-nodes-atlaseye/.npmrc \
  --invert-paths

# 4. Rotacionar os 8 tokens acima
# 5. Armazenar novos valores em GitHub Secrets / Vercel Env Vars / 1Password
# 6. Refatorar deploy.mjs para ler de env vars
```

---

## RLS & autorização

### ✅ O que está correto
- 100% das 27 tabelas têm RLS habilitado.
- Função `is_org_member(org_id)` centraliza verificação de tenant.
- RPCs usam `SECURITY DEFINER` + `SET search_path = ''` (previne injection via search_path).
- PKs compostas `(organization_id, id)` forçam isolação.

### 🔴 Crítico
- `database/018_test_bypass_rls.sql` — policy `USING (true)`. **Nunca aplicar em produção**. Deletar do diretório.
- `database/022_disable_rls_temp.sql` — desabilita RLS inteiramente. Mesmo problema.

### 🟡 Atenção
- Função `is_org_member` concede acesso automático a qualquer superadmin — confirmar que `is_superadmin` só é setado por admins internos e não via signup.
- RPCs `SECURITY DEFINER` devem checar `has_permission()` explicitamente. Auditar as 4 existentes (`delete_pipeline_stage`, `reorder_pipeline_stages`, `remove_member`, `delete_custom_field`).

---

## API surface

### 🔴 Falhas estruturais
- **Sem rate limiting** em `atlas-eye/src/app/api/**`.
- **Sem CORS whitelist**. No MCP HTTP (`atlas-eye-mcp/src/index.ts:52`): `Access-Control-Allow-Origin: *`.
- **Sem CSRF token**. POST/PATCH/DELETE aceitam qualquer origin autenticado.
- **Validação manual** (regex UUID, `parseInt`) em vez de zod. Payloads podem ser malformados.
- **`url.searchParams.getAll('tags')`** aceita arrays ilimitados → DoS.
- **Sem idempotency key** → retries duplicam recursos.

### Endpoints admin expostos (exigem hardening extra)
- `POST /api/admin/create-workspace` — requer JWT superadmin, mas auth check depende de RLS na tabela `profiles`.
- `DELETE /api/admin/delete-workspace` — IRREVERSÍVEL, sem confirmação dupla.
- `POST /api/auth/setup-owner` — retorna setup_token em plaintext.

---

## Webhooks

### 🔴 `supabase/functions/chat-webhook-inbound`
Aceita POST do Uazapi **sem validar origem**. Qualquer um pode injetar mensagens falsas.

**Fix:**
```typescript
import { createHmac } from 'https://deno.land/std@0.178.0/crypto/mod.ts';

const signature = req.headers.get('x-uazapi-signature');
const body = await req.text();
const expected = createHmac('sha256', Deno.env.get('UAZAPI_WEBHOOK_SECRET')!)
  .update(body).digest('hex');

if (signature !== expected) {
  return new Response('Unauthorized', { status: 401 });
}
```

---

## PII & dados sensíveis

- `frontend/screens/*.html` — mockups Stitch com URLs `lh3.googleusercontent.com` contendo fotos/nomes reais. Arquivar ou substituir por placeholders.
- `scripts/sync-avatars.mjs` baixa avatares WhatsApp com números/nomes. Sem anonimização.
- `user_metadata` no Supabase Auth guarda `full_name` sem criptografia (aceitável, mas documentar em GDPR/LGPD).

---

## MCP servers

| Problema | Arquivo | Correção |
|---|---|---|
| CORS `*` | `atlas-eye-mcp/src/index.ts:52` | Whitelist de origens |
| Tools sem try/catch | `atlas-eye-mcp/src/tools/*.ts` | Wrap com erro tipado |
| `setup_owner` sem rate limit | `atlas-eye-mcp/src/tools/auth.ts` | Limit 5/hora por IP |
| `delete_workspace` sem confirmação | `atlas-eye-mcp/src/tools/admin.ts` | Exigir flag `confirm: true` |
| `send_notification` broadcast silencioso | `atlas-eye-mcp/src/tools/notifications.ts:15` | Se `recipient_member_id` vazio, exigir `broadcast: true` explícito |

---

## Checklist de remediação

### Hoje (bloqueador de produção)
- [ ] Rotacionar 8 tokens listados acima
- [ ] Atualizar `.gitignore` e remover arquivos sensíveis do tracking
- [ ] Deletar `database/018_test_bypass_rls.sql` e `database/022_disable_rls_temp.sql`
- [ ] Trocar CORS `*` por whitelist no MCP HTTP
- [ ] Adicionar HMAC no `chat-webhook-inbound`

### Esta semana
- [ ] Migrar secrets para GitHub Secrets + Vercel Env
- [ ] Refatorar `deploy.mjs` para ler SSH key e token de env vars
- [ ] Implementar rate limiting em `/api/**` (Upstash ou `@vercel/ratelimit`)
- [ ] Trocar validação manual por zod schemas em todas as rotas
- [ ] Auditar RPCs `SECURITY DEFINER` para `has_permission()` check
- [ ] Limpar git history dos arquivos sensíveis (git-filter-repo)

### Este mês
- [ ] Adicionar Sentry (frontend + edge functions + MCP)
- [ ] Habilitar 2FA obrigatório no Supabase e npm
- [ ] Documentar plano de resposta a incidente
- [ ] Pentest em staging antes de escalar usuários
- [ ] Configurar backup diário do Postgres com retenção 30d
- [ ] GDPR/LGPD: documentar dados armazenados, política de retenção, direito ao esquecimento
