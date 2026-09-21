# 🗄️ Atlas Eye CRM — Database Schema

**Data:** 2026-03-12 | **Status:** ✅ Atualizado

O banco de dados do Atlas Eye CRM é construído sobre **Supabase (PostgreSQL)** e utiliza **RLS (Row Level Security)** extensivamente para garantir o isolamento multi-tenant (por organização).

Existem atualmente **25 tabelas** principais no schema `public`.

---

## Estrutura Multi-Tenant
Quase todas as entidades do sistema possuem a coluna `organization_id` que faz referência à tabela `organizations`. As políticas RLS garantem que um usuário só possa ler/escrever dados onde o `organization_id` coincida com a organização à qual ele pertence.

---

## 1. Organizações e Planos

- **`organizations`**
  - O locatário raiz (tenant). Tudo se liga aqui.
  - Colunas: `id` (PK, UUID), `name`, `tier_id`, `created_at`, `deleted_at`, `timezone`

- **`tiers`**
  - Planos de assinatura (ex: Free, Pro, Enterprise).
  - Colunas: `id` (PK), `name`, `max_users`, `can_use_custom_fields`, `permissions`

---

## 2. Usuários, Autenticação e Acesso

O sistema utiliza o `auth.users` do Supabase para gerenciar a identidade.

- **`profiles`**
  - Dados estendidos do usuário vinculados 1:1 ao `auth.users`.
  - Colunas: `id` (PK, ref: auth.users), `full_name`, `avatar_url`, `timezone`, `is_superadmin`

- **`organization_members`**
  - O vínculo entre um usuário e uma organização. É o ator principal em associações (ownership, actions).
  - Colunas: `id` (PK, UUID), `organization_id`, `user_id`, `role_id`, `status` (active/invited/disabled)

- **`organization_roles`**
  - RBAC (Role-Based Access Control) por organização.
  - Colunas: `id` (PK), `organization_id`, `name`, `permissions` (JSONB)

- **`setup_tokens`** *(Novo)*
  - Tokens temporários de convite ou configuração de conta.
  - Colunas: `id` (PK), `organization_id`, `token`, `email`, `role`, `expires_at`, `used_at`

- **`api_tokens`** *(Novo)*
  - Tokens Bearer (Começando com `atl_`) para uso de APIs externas como n8n.
  - Colunas: `id` (PK), `organization_id`, `name`, `token_hash`, `created_by`, `last_used_at`, `is_active`

---

## 3. Core CRM: Pipelines e Estágios

- **`pipelines`**
  - Funis de vendas. Uma org pode ter vários pipelines.
  - Colunas: `id` (PK), `organization_id`, `name`, `settings` (JSONB), `deleted_at`

- **`pipeline_stages`**
  - Etapas kanban pertencentes a um pipeline. Usa ranking fracionário para ordenar.
  - Colunas: `id` (PK), `pipeline_id`, `organization_id`, `name`, `color`, `rank`, `target_volume`

---

## 4. Integrações e Webhooks

- **`integrations`**
  - Conexões (ex: WhatsApp, API).
  - Colunas: `id` (PK), `organization_id`, `name`, `type`, `config` (JSONB), `status`

- **`webhook_logs`** *(Novo)*
  - Auditoria e diagnóstico de eventos recebidos (ex: WhatsApp inbounds).
  - Colunas: `id` (PK), `organization_id`, `integration_id`, `payload` (JSONB), `status`, `error`, `created_at`

---

## 5. Leads (Contatos/Oportunidades)

- **`leads`**
  - A entidade central. Um lead pertence a um estágio em um pipeline.
  - Colunas Principais: `id` (PK), `organization_id`, `stage_id`, `owner_member_id`
  - Dados do Cliente: `title`, `email`, `phone`, `external_id`
  - Estados UI: `is_pinned`, `is_unread`, `avatar_url`
  - IA & Resumo: `ai_interest_level`, `ai_next_action_short`
  - Atividades (Desnormalizado para performance): `last_activity_at`, `last_activity_type`, `custom_attributes` (JSONB)

- **`lead_ai_insights`**
  - Dados profundos gerados por agentes IA para o lead 1:1.
  - Colunas: `id` (PK), `organization_id`, `lead_id`, `summary`, `interest_level`, `next_action`, `generated_at`

- **`tags`**
  - Etiquetas coloridas por tenant.
  - Colunas: `id` (PK), `organization_id`, `name`, `color`

- **`lead_tags`**
  - Relação N:N entre leads e tags.
  - Colunas: `organization_id`, `lead_id`, `tag_id` (PK composta)

---

## 6. Histórico e Atividades Multicanais

- **`lead_activities`**
  - Timeline consolidada de todas as interações (mensagens, notas, mudanças sistêmicas).
  - Colunas: `id` (PK), `organization_id`, `lead_id`, `actor_member_id`, `type` (whatsapp/email/call/note/system), `content` (TEXT), `metadata` (JSONB), `created_at`

- **`lead_stage_history`**
  - Registro de auditoria quando um lead muda de coluna (drag & drop).
  - Colunas: `id` (PK), `organization_id`, `lead_id`, `from_stage_id`, `to_stage_id`, `changed_by_member_id`, `changed_at`

---

## 7. Custom Fields (Campos Personalizados)

- **`custom_field_categories`** *(Novo)*
  - Agrupamento de campos na UI (ex: "Dados do Lead", "Endereço").
  - Colunas: `id` (PK), `organization_id`, `name`, `rank`

- **`custom_field_definitions`**
  - Metadados do campo definido pelo usuário (Tipos permitidos: text, number, date, bool, select, multi_select).
  - Colunas: `id` (PK), `organization_id`, `category_id`, `name`, `key` (slug único), `field_type`, `schema` (JSONB - guarda options do dropdown), `is_indexed`

- **`custom_field_index_values`**
  - Valores fortemente tipados caso seja necessário realizar Queries SQL complexas ou indexações (geralmente também salvos de forma plana em `leads.custom_attributes`).
  - Colunas: `id` (PK), `organization_id`, `lead_id`, `field_id`, `value_text`, `value_number`, `value_date`, `value_bool`, `value_json`

---

## 8. Notificações e UI

- **`notifications`**
  - Inbox de notificações do usuário no sistema.
  - Colunas: `id` (PK), `organization_id`, `recipient_member_id`, `actor_member_id`, `type`, `title`, `content`, `link_url`, `is_read`, `created_at`

- **`user_notification_settings`**
  - Preferências individuais.
  - Colunas: `id` (PK), `member_id`, `new_lead_alert`, `last_stage_alert`, `no_response_24h_alert` (entre outras)

- **`automation_settings`**
  - Regras no nível da organização (ex: Integrações de IA ativadas ou regras de round-robin).
  - Colunas: `id` (PK), `organization_id`, `key`, `is_enabled`, `variables` (JSONB)

- **`ui_state_drafts`**
  - Rascunhos automáticos (ex: texto do chat não enviado salvo per user/lead).
  - Colunas: `id` (PK), `organization_id`, `member_id`, `page_slug`, `draft_data` (JSONB)

- **`audit_logs`**
  - Log geral e inflexível para compliance (geralmente usado de forma esporádica).
  - Colunas: `id`, `organization_id`, `actor_member_id`, `action`, `entity_type`, `entity_id`, `old_values`, `new_values`

---

## 9. Search Infrastructure (Lead Filter)

Suporte a busca acento-insensível e por dígitos de telefone na sidebar de Chat e em mensagens (`whatsapp`/`email`). Definido na spec `docs/superpowers/specs/2026-04-13-lead-filter-design.md`.

### Extensões
- **`pg_trgm`** — já presente no schema `extensions`.
- **`unaccent`** *(Novo)* — instalada em `extensions`. Necessária para normalização acento-insensível.

### Funções Auxiliares (IMMUTABLE)
- **`public.leads_phone_digits(p text) RETURNS text`** *(Novo)*
  - Remove todos os caracteres não-numéricos (`regexp_replace(..., '\D', '', 'g')`).
  - `IMMUTABLE PARALLEL SAFE` — usada tanto em índice de expressão quanto em queries para garantir match exato.
- **`public.norm_text(p text) RETURNS text`** *(Novo)*
  - Aplica `extensions.unaccent('extensions.unaccent'::regdictionary, lower(coalesce(p,'')))` — o cast explícito para `regdictionary` é necessário porque o dicionário `unaccent` reside em `extensions`.
  - `IMMUTABLE PARALLEL SAFE` com `SET search_path = extensions, public` — sem o `search_path` fixado, o dicionário `unaccent` não é resolvido a partir do escopo de uma SQL function. Base para os índices trigram acento-insensíveis.

### Índices GIN Trigram *(Novo)*
Todos criados com `CONCURRENTLY` e `gin_trgm_ops`:

- **`idx_leads_title_trgm`** em `leads(public.norm_text(title))`, parcial `WHERE deleted_at IS NULL`.
- **`idx_leads_email_trgm`** em `leads(public.norm_text(email))`, parcial `WHERE deleted_at IS NULL`.
- **`idx_leads_phone_digits_trgm`** em `leads(public.leads_phone_digits(phone))`, parcial `WHERE deleted_at IS NULL`.
- **`idx_activities_content_trgm`** em `lead_activities(public.norm_text(content))`, parcial `WHERE type IN ('whatsapp','email') AND content IS NOT NULL`.

Os índices parciais excluem leads soft-deletados e atividades de tipos irrelevantes (`note`/`call`/`system`) para mantê-los compactos. Os quatro índices estão presentes e marcados como `VALID` em `pg_index.indisvalid` (verificado pelo smoke suite).

### RPC: `public.search_leads` *(Novo)*

```
search_leads(
  p_org           uuid,
  p_q             text,
  p_view_own_only boolean DEFAULT false,
  p_member_id     uuid    DEFAULT NULL,
  p_limit         int     DEFAULT 50
) RETURNS TABLE (
  lead_id    uuid,
  match_type text,         -- 'title' | 'email' | 'phone' | 'message'
  snippet    text,         -- preenchido apenas quando match_type='message'
  matched_at timestamptz,  -- created_at da mensagem casada
  lead       jsonb         -- linha completa do lead para hidratação no client
)
```

- `LANGUAGE plpgsql STABLE`, **`SECURITY INVOKER`** — RLS de `leads` e `lead_activities` continua ativa.
- `SET search_path = public, extensions`.
- Diretiva `#variable_conflict use_column` no topo do corpo `plpgsql` — necessária porque os nomes das colunas em `RETURNS TABLE` (`lead_id`, `match_type`, `snippet`, `matched_at`) colidem com aliases homônimos das CTEs internas; a diretiva faz o parser resolver referências ambíguas para as colunas das CTEs em vez das variáveis de saída.
- Curto-circuita se `length(norm_text(p_q)) < 3`.
- CTE `lead_hits`: ILIKE com `norm_text` em `title`/`email` + ILIKE em `leads_phone_digits(phone)` quando `length(digits(p_q)) >= 3`.
- CTE `msg_hits`: ILIKE com `norm_text` em `lead_activities.content` (tipos `whatsapp`/`email`), com `DISTINCT ON (lead_id) ORDER BY created_at DESC` para retornar a mensagem mais recente por lead.
- Resultado final: `lead_hits UNION ALL (msg_hits - lead_hits)` com `LIMIT p_limit`.
- O parâmetro `p_view_own_only`/`p_member_id` é defesa-em-profundidade na camada de aplicação (a RLS de `leads` não impõe ownership por si só).
- `GRANT EXECUTE ... TO authenticated`.

Migration file: `database/026_lead_search.sql`. Applied helper scripts: `scripts/apply-026.mjs` (DDL runner) e `scripts/smoke-026.mjs` (13-check smoke suite).

---

*Regras de Ouro de Inserção:*
1. Todo INSERT de API obrigatoriamente valida se a entidade pertence à `auth.organizationId`.
2. O RLS garante que o supabase-js (client) faça isso implicitamente no lado do usuário.
3. Chaves primárias UUIDv4 preferenciais a Auto Increment.