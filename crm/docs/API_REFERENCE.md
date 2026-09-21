# 🔌 Atlas Eye CRM — API Reference

**Data:** 2026-03-12 | **Status:** ✅ Completo (20 rotas)

O Atlas Eye CRM fornece uma API REST completa para integrações externas (como n8n) e consumo pelo próprio frontend. Todas as requisições exigem autenticação baseada na Organização do usuário.

## Autenticação

Todas as rotas sob `/api/*` aceitam o header `Authorization: Bearer <token>`. O token pode ser de dois tipos:

1. **Supabase JWT:** Token de sessão do usuário (Frontend).
2. **API Token:** Token emitido no painel de integrações, com o prefixo `atl_` (Integrações backend/n8n).

Exemplo de requisição:
```bash
curl -X GET https://seu-dominio.com/api/leads \
  -H "Authorization: Bearer atl_12345abcdef"
```

---

## 👥 Leads & CRM

### `GET /api/leads`
Lista leads da organização. Suporta busca, paginação e filtros.
- **Query Params:**
  - `page` (default: 1)
  - `limit` (default: 20, max 100)
  - `q` (busca por nome, email ou telefone)
  - `phone` (filtro exato ou parcial)
  - `assigned_to` (ID do owner)
  - `returnAll=true` (ignora paginação)

### `POST /api/leads`
Cria um novo lead.
- **Body:** `{ title, phone, email, source, custom_fields, tags, ... }`
- **Requisito:** `source` é obrigatório (ex: `api`, `system`). Se o lead já existir pelo telefone, a API pode atualizar ou avisar dependendo da regra de upsert.

### `POST /api/leads/search`
Busca avançada de leads por título, email, telefone (dígitos normalizados) e conteúdo de mensagens (`whatsapp`/`email`). Usada pelo filtro do `LeadList` no Chat. **Distinta** da rota legada `GET /api/leads?q=`, que continua atendendo o `GlobalSearch`.
- **Auth:** Sessão obrigatória (401 se ausente).
- **Body:** `{ q: string, limit?: number }` — `q` deve ter no mínimo 3 caracteres; `limit` default 50.
- **Resposta:** `{ hits: Array<{ lead: LeadWithOwner, matchType: 'title' | 'email' | 'phone' | 'message', snippet?: string, matchedAt?: string }> }`. `snippet` e `matchedAt` só vêm quando `matchType === 'message'`.
- **Status:** implementado 2026-04-13. Auth via `authenticateRequest`; Supabase chamado com `createSupabaseAdmin`; `view_own_only` derivado das permissions de `organization_roles`. Rota independente — não afeta o legado `GET /api/leads?q=` usado pelo `GlobalSearch`.
- **Comportamento:** Respeita `permissions.leads.view_own_only`. Internamente chama o RPC `search_leads` (accent/case-insensitive via `unaccent`).
- **Erros:**
  | Código | Causa |
  |---|---|
  | 400 | `q` com menos de 3 caracteres |
  | 401 | Sem sessão válida |
  | 500 | Falha no RPC `search_leads` |

### `GET /api/leads/[id]`
Busca um lead específico. O `[id]` pode ser o UUID do lead ou o `phone` na URL (url-encoded).

### `PATCH /api/leads/[id]`
Atualiza um lead existente (UUID ou phone).
- **Body:** `{ title, stage_id, custom_fields, tags, source }`
- **Comportamento:** Se passar o `phone` na URL e ele não existir, a API **cria** no primeiro estágio. Se passar UUID e não existir, retorna 404.

### `DELETE /api/leads/[id]`
Soft-delete de um lead (preenche `deleted_at`).

### `GET /api/leads/[id]/messages`
Busca todas as mensagens/atividades do tipo WhatsApp/Email anexadas ao lead.

### `POST /api/leads/[id]/messages`
Adiciona uma nova mensagem à timeline do lead.
- **Body:** `{ content, type: 'whatsapp' | 'note', metadata, source }`

### `GET /api/leads/[id]/history`
Retorna o histórico unificado do lead: mudanças de estágio + timeline de atividades.

### `GET /api/leads/history/[event_id]`
Busca os detalhes de um evento de histórico específico.

---

## 📊 Pipelines e Estágios

### `GET /api/pipelines`
Lista todos os fluxos de venda/atendimento com suas configurações e estágios (ordenados por rank).

### `POST /api/pipelines`
Cria um novo funil Kanban.
- **Body:** `{ name, settings, source }`

### `GET /api/pipelines/[id]`
Retorna um funil específico.

### `PATCH /api/pipelines/[id]`
Renomeia ou ajusta settings de um funil.

### `DELETE /api/pipelines/[id]`
Deleta um pipeline e seus estágios (Soft-delete).

### `GET /api/pipelines/[id]/stages`
Lista apenas os estágios de um pipeline. Usado para popular dropdowns rápídos.

### `PATCH /api/pipelines/stages/[stage_id]`
Atualiza propriedades de um estágio específico.
- **Body:** `{ name, rank, color, target_volume, source }`

### `GET /api/pipelines/stage-colors`
Retorna a paleta de cores disponível para os estágios.

---

## 📋 Campos Personalizados (Custom Fields)

### `GET /api/custom-fields`
Lista todos os `custom_field_definitions` da organização, incluindo categorias e schema de opções (para dropdowns/selects).

### `GET /api/custom-fields/[id]`
Retorna a definição tipada de um campo específico.

---

## 🏷️ Tags

### `GET /api/tags`
Lista todas as tags cadastradas (útil para dropdowns no n8n).

### `POST /api/tags`
Cria uma nova tag na organização.
- **Body:** `{ name, color, source }`

---

## 👥 Membros de Equipe (Users)

### `GET /api/users`
Lista todos os `organization_members` ativos e convidados, trazendo `full_name` e `avatar_url` da tabela profiles.

### `GET /api/users/[member_id]`
Busca os detalhes de permissão e perfil de um membro.

### `PATCH /api/users/[member_id]`
Atualiza role/permissões ou inativa um membro.

---

## 🔔 Notificações & Automações

### `GET /api/notifications`
Lista as notificações do usuário logado (is_read = false por padrão).

### `PATCH /api/notifications`
Marca notificações como lidas.
- **Body:** `{ ids: [...], markAllAsRead: boolean }`

### `POST /api/notifications`
Dispara uma notificação in-app (via websocket/DB) para membros da org baseada em `event_id` definidos na tabela `automation_settings`.
- **Body:** `{ event_id, source }`

---

## 🛠️ Admin / Setup

> ⚠️ Requerem token de Super Admin ou token JWT de primeira configuração temporal (`setup_tokens`).

### `POST /api/auth/setup-owner`
Finaliza o setup do dono do workspace (Full Name, Password) utilizando um `setup_token`.

### `POST /api/admin/create-workspace`
Cria o locatário, seta os `tiers`, injeta o `setup_token` primário e estrutura as tabelas base da nova organização.

### `DELETE /api/admin/delete-workspace`
Limpa toda a org (uso destrutivo).

---

## 📖 Documentação Endpoints Dinâmicos

### `GET /api/docs`
Retorna uma versão JSON rudimentar deste documento na própria rota.
