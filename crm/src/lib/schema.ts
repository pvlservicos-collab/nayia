/**
 * Drizzle ORM Schema — TitaCRM
 * Espelha exatamente as migrations SQL do Supabase (database/001_init_schema.sql + seguintes)
 * compatível com Neon (PostgreSQL)
 */
import {
  pgTable, pgEnum, uuid, text, boolean, integer, numeric,
  timestamp, jsonb, index, uniqueIndex, foreignKey, primaryKey,
} from 'drizzle-orm/pg-core'
import { sql } from 'drizzle-orm'

// ── Enums ────────────────────────────────────────────────────────────────────
export const memberStatusEnum = pgEnum('member_status', ['active', 'invited', 'disabled'])
export const integrationStatusEnum = pgEnum('integration_status', ['active', 'disabled'])
export const leadActivityTypeEnum = pgEnum('lead_activity_type', ['note', 'call', 'whatsapp', 'email', 'system'])
export const customFieldTypeEnum = pgEnum('custom_field_type', ['text', 'number', 'date', 'bool', 'select', 'multi_select', 'json'])

// ── Tiers & Organizations ─────────────────────────────────────────────────────
export const tiers = pgTable('tiers', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  maxUsers: integer('max_users'),
  canUseCustomFields: boolean('can_use_custom_fields').default(false),
  permissions: jsonb('permissions').default({}),
})

export const organizations = pgTable('organizations', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  tierId: uuid('tier_id').references(() => tiers.id),
  timezone: text('timezone').default('UTC'),
  logoUrl: text('logo_url'),
  // Controlado manualmente pelo painel /admin por enquanto (sem gateway de
  // pagamento integrado ainda): 'active' | 'unpaid' | 'cancelled'.
  subscriptionStatus: text('subscription_status').notNull().default('active'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Auth & Profiles ───────────────────────────────────────────────────────────
// Substitui auth.users do Supabase — gerenciado pelo NextAuth + bcrypt
export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  email: text('email').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

export const profiles = pgTable('profiles', {
  id: uuid('id').primaryKey().references(() => users.id, { onDelete: 'cascade' }),
  fullName: text('full_name'),
  avatarUrl: text('avatar_url'),
  timezone: text('timezone'),
  isSuperadmin: boolean('is_superadmin').default(false),
  // Não usado pra travar navegação (a página "Início" é livre, sem gate) — mantido
  // como sinal leve/opcional, sem nenhuma tela dependendo dele hoje.
  onboardingCompleted: boolean('onboarding_completed').default(false),
})

// Tabela de sessões NextAuth (necessária para estratégia database)
export const sessions = pgTable('sessions', {
  id: uuid('id').defaultRandom().primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  token: text('token').notNull().unique(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── RBAC ──────────────────────────────────────────────────────────────────────
export const organizationRoles = pgTable('organization_roles', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  permissions: jsonb('permissions').default({}),
  version: integer('version').default(1),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

export const organizationMembers = pgTable('organization_members', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  userId: uuid('user_id').notNull().references(() => profiles.id),
  roleId: uuid('role_id').notNull(),
  status: memberStatusEnum('status').default('active'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Pipelines ─────────────────────────────────────────────────────────────────
export const pipelines = pgTable('pipelines', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  settings: jsonb('settings').default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

export const pipelineStages = pgTable('pipeline_stages', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull(),
  pipelineId: uuid('pipeline_id').notNull().references(() => pipelines.id),
  name: text('name').notNull(),
  color: text('color'),
  rank: numeric('rank', { precision: 20, scale: 6 }).notNull(),
  targetVolume: integer('target_volume'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Integrations ──────────────────────────────────────────────────────────────
export const integrations = pgTable('integrations', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  type: text('type'),
  config: jsonb('config').default({}),
  status: integrationStatusEnum('status').default('active'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// Segredos das integrações (substitui vault do Supabase)
export const integrationSecrets = pgTable('integration_secrets', {
  id: uuid('id').defaultRandom().primaryKey(),
  integrationId: uuid('integration_id').notNull().references(() => integrations.id, { onDelete: 'cascade' }),
  organizationId: uuid('organization_id').notNull(),
  secret: jsonb('secret').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

// ── Leads ─────────────────────────────────────────────────────────────────────
export const leads = pgTable('leads', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  stageId: uuid('stage_id'),
  integrationId: uuid('integration_id'),
  ownerMemberId: uuid('owner_member_id'),
  title: text('title').notNull(),
  externalId: text('external_id'),
  email: text('email'),
  phone: text('phone'),
  avatarUrl: text('avatar_url'),
  cpf: text('cpf'),
  cep: text('cep'),
  address: text('address'),
  addressNumber: text('address_number'),
  addressComplement: text('address_complement'),
  neighborhood: text('neighborhood'),
  city: text('city'),
  state: text('state'),
  aiInterestLevel: text('ai_interest_level'),
  aiNextActionShort: text('ai_next_action_short'),
  customAttributes: jsonb('custom_attributes').default({}),
  lastMessageContent: text('last_message_content'),
  lastMessageSenderType: text('last_message_sender_type'),
  lastActivityAt: timestamp('last_activity_at', { withTimezone: true }),
  lastActivityType: leadActivityTypeEnum('last_activity_type'),
  lastActivityByMemberId: uuid('last_activity_by_member_id'),
  isGroup: boolean('is_group').default(false),
  isUnread: boolean('is_unread').default(false),
  isPinned: boolean('is_pinned').default(false),
  isArchived: boolean('is_archived').default(false),
  value: numeric('value', { precision: 15, scale: 2 }),
  goals: jsonb('goals').default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
}, (t) => ({
  // Defesa real contra lead duplicado: SELECT-then-INSERT por telefone/external_id em
  // vários webhooks concorrentes já criou lead repetido pro mesmo contato (ex: 2 leads
  // "Geicymara Alves" com o mesmo telefone, criados a 1ms de diferença). Índices já
  // aplicados diretamente no Neon via script; declarados aqui só pra manter o schema
  // Drizzle fiel ao banco real (não roda migration automática neste projeto).
  orgPhoneUnique: uniqueIndex('leads_org_phone_unique').on(t.organizationId, t.phone)
    .where(sql`deleted_at IS NULL AND phone IS NOT NULL AND phone != ''`),
  integrationExternalIdUnique: uniqueIndex('leads_integration_external_id_unique').on(t.integrationId, t.externalId)
    .where(sql`deleted_at IS NULL AND external_id IS NOT NULL`),
}))

// ── Tags ──────────────────────────────────────────────────────────────────────
export const tags = pgTable('tags', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  color: text('color').default('#6366f1'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

export const leadTags = pgTable('lead_tags', {
  leadId: uuid('lead_id').notNull().references(() => leads.id, { onDelete: 'cascade' }),
  tagId: uuid('tag_id').notNull().references(() => tags.id, { onDelete: 'cascade' }),
  organizationId: uuid('organization_id').notNull(),
}, (t) => ({
  pk: primaryKey({ columns: [t.leadId, t.tagId] }),
}))

// ── Lead Activities ───────────────────────────────────────────────────────────
export const leadActivities = pgTable('lead_activities', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  leadId: uuid('lead_id').notNull().references(() => leads.id, { onDelete: 'cascade' }),
  actorMemberId: uuid('actor_member_id'),
  type: leadActivityTypeEnum('type').notNull(),
  content: text('content'),
  metadata: jsonb('metadata').default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  // Mesma defesa que leads_org_phone_unique, só que pra mensagem: um webhook duplicado
  // (mesmo evolution_message_id/whatsapp_message_id/instagram_message_id) já criou
  // activity repetida — inclusive batendo em dois leads diferentes de uma vez, quando a
  // resolução de telefone divergiu entre as duas entregas do mesmo webhook. Único
  // global (não por lead), de propósito. Índices já aplicados no Neon via script.
  evolutionMsgIdUnique: uniqueIndex('lead_activities_evolution_msgid_unique').on(sql`(metadata->>'evolution_message_id')`)
    .where(sql`metadata->>'evolution_message_id' IS NOT NULL`),
  whatsappMsgIdUnique: uniqueIndex('lead_activities_whatsapp_msgid_unique').on(sql`(metadata->>'whatsapp_message_id')`)
    .where(sql`metadata->>'whatsapp_message_id' IS NOT NULL`),
  instagramMsgIdUnique: uniqueIndex('lead_activities_instagram_msgid_unique').on(sql`(metadata->>'instagram_message_id')`)
    .where(sql`metadata->>'instagram_message_id' IS NOT NULL`),
  zapiMsgIdUnique: uniqueIndex('lead_activities_zapi_msgid_unique').on(sql`(metadata->>'zapi_message_id')`)
    .where(sql`metadata->>'zapi_message_id' IS NOT NULL`),
}))

// ── Mensagens Fixadas ─────────────────────────────────────────────────────────
// Tabela separada (em vez de metadata da activity) para não concorrer com outros
// escritores de metadata (reply, reações, status de envio) e para permitir
// listar/paginar fixadas sem varrer a conversa inteira. Sem limite de quantidade.
export const pinnedMessages = pgTable('pinned_messages', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  leadId: uuid('lead_id').notNull().references(() => leads.id, { onDelete: 'cascade' }),
  activityId: uuid('activity_id').notNull().references(() => leadActivities.id, { onDelete: 'cascade' }),
  pinnedByMemberId: uuid('pinned_by_member_id'),
  pinnedAt: timestamp('pinned_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  leadActivityUnique: uniqueIndex('pinned_messages_lead_activity_unique').on(t.leadId, t.activityId),
  leadPinnedAtIdx: index('pinned_messages_lead_pinned_at_idx').on(t.leadId, t.pinnedAt),
}))

// ── Custom Fields ─────────────────────────────────────────────────────────────
export const customFieldCategories = pgTable('custom_field_categories', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  rank: numeric('rank', { precision: 20, scale: 6 }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

export const customFieldDefinitions = pgTable('custom_field_definitions', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  categoryId: uuid('category_id').references(() => customFieldCategories.id),
  name: text('name').notNull(),
  fieldKey: text('field_key').notNull(),
  fieldType: customFieldTypeEnum('field_type').notNull(),
  options: jsonb('options').default([]),
  isRequired: boolean('is_required').default(false),
  rank: numeric('rank', { precision: 20, scale: 6 }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Lead History ──────────────────────────────────────────────────────────────
export const leadStageHistory = pgTable('lead_stage_history', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull(),
  leadId: uuid('lead_id').notNull().references(() => leads.id, { onDelete: 'cascade' }),
  fromStageId: uuid('from_stage_id'),
  toStageId: uuid('to_stage_id'),
  movedByMemberId: uuid('moved_by_member_id'),
  movedAt: timestamp('moved_at', { withTimezone: true }).defaultNow(),
})

// ── Configuração da IA ────────────────────────────────────────────────────────
// Uma linha por organização. Nasce DESLIGADA de propósito: o prompt pode ser
// escrito e revisado com calma antes de qualquer coisa responder cliente no
// lugar de uma pessoa. Nada no app lê esta tabela ainda — ela guarda a
// configuração pra quando a IA for conectada.
// Aplicada por drizzle/0121_ai_settings.sql.
export const aiSettings = pgTable('ai_settings', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  enabled: boolean('enabled').notNull().default(false),
  model: text('model').notNull().default('claude-opus-5'),
  systemPrompt: text('system_prompt').notNull().default(''),
  guardrails: text('guardrails').notNull().default(''),
  updatedByMemberId: uuid('updated_by_member_id'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  orgUnique: uniqueIndex('ai_settings_org_unique').on(t.organizationId),
}))

// ── API Tokens ────────────────────────────────────────────────────────────────
export const apiTokens = pgTable('api_tokens', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  tokenHash: text('token_hash').notNull().unique(),
  isActive: boolean('is_active').default(true),
  lastUsedAt: timestamp('last_used_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── Lead Source Submissions (leads recebidos de fontes externas) ─────────────
// Log cru do que cada fonte mandou. Campos de contato em colunas (iguais em toda
// fonte, é o que a tela lista e o que liga no lead do CRM); o resto em `payload`,
// pra fonte nova não exigir migration. Registro das fontes: src/lib/leadSources.ts.
// Aplicado no banco por drizzle/0119_lead_source_submissions.sql (este projeto
// não roda migration automática).
export const leadSourceSubmissions = pgTable('lead_source_submissions', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  source: text('source').notNull(),
  externalId: text('external_id'),
  name: text('name'),
  email: text('email'),
  phone: text('phone'),
  instagram: text('instagram'),
  payload: jsonb('payload').notNull().default({}),
  leadId: uuid('lead_id'),
  // Quem já foi abordado pelo botão "Enviar mensagem" da lista. Fica aqui e não
  // em `leads` porque a marca é sobre a linha da lista ter sido trabalhada — o
  // lead recebe mensagem por vários outros caminhos sem que isso conte.
  contactedAt: timestamp('contacted_at', { withTimezone: true }),
  contactedByMemberId: uuid('contacted_by_member_id'),
  receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  // O ON CONFLICT do endpoint de ingestão depende deste índice: reenviar o mesmo
  // lead (quiz que era "w1" e virou "done") atualiza a linha em vez de duplicar.
  dedupeUnique: uniqueIndex('lead_source_submissions_dedupe_unique')
    .on(t.organizationId, t.source, t.externalId)
    .where(sql`external_id IS NOT NULL`),
  // Existe ainda lead_source_submissions_org_source_idx
  // (organization_id, source, received_at DESC), que serve a listagem da tela.
  // Aplicado por SQL (drizzle/0119) e não declarado aqui porque o drizzle-kit
  // desta versão não aceita ordem por coluna no índice — mesmo caminho que a
  // tabela `leads` já usa pros índices dela.
}))

// ── Integration Message Logs (n8n e outros sistemas externos) ────────────────
export const integrationMessageLogs = pgTable('integration_message_logs', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  source: text('source').notNull(),
  direction: text('direction'),
  phone: text('phone'),
  content: text('content'),
  leadId: uuid('lead_id'),
  status: text('status').notNull(),
  error: text('error'),
  payload: jsonb('payload'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── Notifications ─────────────────────────────────────────────────────────────
export const notifications = pgTable('notifications', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  recipientMemberId: uuid('recipient_member_id').notNull(),
  type: text('type').notNull(),
  title: text('title').notNull(),
  body: text('body'),
  metadata: jsonb('metadata').default({}),
  isRead: boolean('is_read').default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// Inscrições de push (Web Push/VAPID) — uma linha por navegador/aparelho. Chave única
// em endpoint (não em member_id): um aparelho compartilhado pode trocar de dono, o
// upsert por endpoint resolve isso sozinho, e é o mesmo campo usado pra limpar
// inscrições mortas quando o navegador reporta 404/410.
export const pushSubscriptions = pgTable('push_subscriptions', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  memberId: uuid('member_id').notNull(),
  endpoint: text('endpoint').notNull(),
  p256dh: text('p256dh').notNull(),
  auth: text('auth').notNull(),
  userAgent: text('user_agent'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  lastSeenAt: timestamp('last_seen_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  endpointUnique: uniqueIndex('push_subscriptions_endpoint_unique').on(t.endpoint),
  memberIdx: index('push_subscriptions_member_idx').on(t.memberId),
  orgIdx: index('push_subscriptions_org_idx').on(t.organizationId),
}))

// ── Setup Tokens (para criação inicial de workspace) ──────────────────────────
export const setupTokens = pgTable('setup_tokens', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  token: text('token').notNull().unique(),
  usedAt: timestamp('used_at', { withTimezone: true }),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  // Null = comportamento antigo (sempre "Admin"). Permite gerar convite pra um papel
  // específico da própria org (ex: "Founder", acesso total, pra um segundo dono).
  roleName: text('role_name'),
})

// ── Webhook Logs ──────────────────────────────────────────────────────────────
export const webhookLogs = pgTable('webhook_logs', {
  id: uuid('id').defaultRandom().primaryKey(),
  payload: jsonb('payload'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── Funil de Mensagens ────────────────────────────────────────────────────────
// 'lead_site_evento' / 'lead_agenda_ascensao' disparam quando um lead novo entra
// por /api/ingest/leads (ver src/lib/funnel-triggers.ts). Aplicados no banco por
// drizzle/0120_funnel_lead_sources.sql.
export const funnelTriggerEnum = pgEnum('funnel_trigger', ['novo_pago', 'novo_recuperacao', 'geracaowhatsapp', 'pedido_figurinha', 'abandono_preco', 'lead_site_evento', 'lead_agenda_ascensao'])
// 'move_stage' move o lead de etapa no pipeline; config = { stageId }.
export const funnelBlockTypeEnum = pgEnum('funnel_block_type', ['trigger', 'message', 'wait', 'condition', 'end', 'move_stage'])
export const funnelBranchEnum = pgEnum('funnel_branch', ['default', 'yes', 'no'])
export const funnelExecutionStatusEnum = pgEnum('funnel_execution_status', ['running', 'waiting', 'waiting_condition', 'completed', 'stopped'])

export const messageFunnels = pgTable('message_funnels', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  trigger: funnelTriggerEnum('trigger').notNull(),
  isActive: boolean('is_active').default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

export const funnelBlocks = pgTable('funnel_blocks', {
  id: uuid('id').defaultRandom().primaryKey(),
  funnelId: uuid('funnel_id').notNull().references(() => messageFunnels.id, { onDelete: 'cascade' }),
  type: funnelBlockTypeEnum('type').notNull(),
  config: jsonb('config').default({}),
  positionX: numeric('position_x', { precision: 10, scale: 2 }).default('0'),
  positionY: numeric('position_y', { precision: 10, scale: 2 }).default('0'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

export const funnelConnections = pgTable('funnel_connections', {
  id: uuid('id').defaultRandom().primaryKey(),
  funnelId: uuid('funnel_id').notNull().references(() => messageFunnels.id, { onDelete: 'cascade' }),
  sourceBlockId: uuid('source_block_id').notNull().references(() => funnelBlocks.id, { onDelete: 'cascade' }),
  targetBlockId: uuid('target_block_id').notNull().references(() => funnelBlocks.id, { onDelete: 'cascade' }),
  branch: funnelBranchEnum('branch').default('default'),
})

export const funnelExecutions = pgTable('funnel_executions', {
  id: uuid('id').defaultRandom().primaryKey(),
  funnelId: uuid('funnel_id').notNull().references(() => messageFunnels.id, { onDelete: 'cascade' }),
  organizationId: uuid('organization_id').notNull(),
  leadId: uuid('lead_id').notNull().references(() => leads.id, { onDelete: 'cascade' }),
  currentBlockId: uuid('current_block_id'),
  status: funnelExecutionStatusEnum('status').default('running'),
  waitUntil: timestamp('wait_until', { withTimezone: true }),
  context: jsonb('context').default({}),
  startedAt: timestamp('started_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})

export const funnelClickEvents = pgTable('funnel_click_events', {
  id: uuid('id').defaultRandom().primaryKey(),
  executionId: uuid('execution_id').notNull().references(() => funnelExecutions.id, { onDelete: 'cascade' }),
  blockId: uuid('block_id').notNull(),
  token: text('token').notNull().unique(),
  targetUrl: text('target_url').notNull(),
  clicked: boolean('clicked').default(false),
  clickedAt: timestamp('clicked_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

export const funnelResponseEvents = pgTable('funnel_response_events', {
  id: uuid('id').defaultRandom().primaryKey(),
  executionId: uuid('execution_id').notNull().references(() => funnelExecutions.id, { onDelete: 'cascade' }),
  blockId: uuid('block_id').notNull(),
  branch: funnelBranchEnum('branch').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── Produtos ──────────────────────────────────────────────────────────────────
export const products = pgTable('products', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  name: text('name').notNull(),
  description: text('description'),
  price: numeric('price', { precision: 15, scale: 2 }).notNull().default('0'),
  status: text('status').notNull().default('active'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Pedidos ───────────────────────────────────────────────────────────────────
export const orders = pgTable('orders', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  leadId: uuid('lead_id').references(() => leads.id, { onDelete: 'set null' }),
  paymentMethod: text('payment_method').notNull().default('pix'),
  paymentStatus: text('payment_status').notNull().default('pending'),
  deliveryStatus: text('delivery_status').notNull().default('pending'),
  totalValue: numeric('total_value', { precision: 15, scale: 2 }).notNull().default('0'),
  notes: text('notes'),
  customerName: text('customer_name'),
  customerPhone: text('customer_phone'),
  customerEmail: text('customer_email'),
  customerCpf: text('customer_cpf'),
  customerCep: text('customer_cep'),
  customerAddress: text('customer_address'),
  customerAddressNumber: text('customer_address_number'),
  customerAddressComplement: text('customer_address_complement'),
  customerNeighborhood: text('customer_neighborhood'),
  customerCity: text('customer_city'),
  customerState: text('customer_state'),
  // Dinheiro em espécie: o motoboy recebe fisicamente na entrega, então "pago" não
  // significa "já está com a empresa" — cashSettled controla esse repasse à parte.
  // Default true pra não afetar pedidos existentes/outros métodos de pagamento;
  // só pedidos novos em dinheiro nascem com false (ver POST /api/orders).
  cashSettled: boolean('cash_settled').notNull().default(true),
  cashSettledAt: timestamp('cash_settled_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deliveredAt: timestamp('delivered_at', { withTimezone: true }),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
})

// ── Itens do Pedido ───────────────────────────────────────────────────────────
export const orderItems = pgTable('order_items', {
  id: uuid('id').defaultRandom().primaryKey(),
  orderId: uuid('order_id').notNull().references(() => orders.id, { onDelete: 'cascade' }),
  organizationId: uuid('organization_id').notNull(),
  productId: uuid('product_id').references(() => products.id, { onDelete: 'set null' }),
  productName: text('product_name').notNull(),
  quantity: integer('quantity').notNull().default(1),
  unitPrice: numeric('unit_price', { precision: 15, scale: 2 }).notNull().default('0'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
})

// ── Respostas Rápidas ─────────────────────────────────────────────────────────
export const quickReplyScopeEnum = pgEnum('quick_reply_scope', ['shared', 'personal'])

export const quickReplies = pgTable('quick_replies', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  scope: quickReplyScopeEnum('scope').notNull().default('personal'),
  createdByMemberId: uuid('created_by_member_id'),
  shortcut: text('shortcut').notNull(),
  category: text('category'),
  content: text('content').notNull().default(''),
  mediaUrl: text('media_url'),
  mediaType: text('media_type'),
  mediaMimetype: text('media_mimetype'),
  mediaFilename: text('media_filename'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
}, (t) => ({
  orgScopeIdx: index('quick_replies_org_scope_idx').on(t.organizationId, t.scope),
  orgMemberIdx: index('quick_replies_org_member_idx').on(t.organizationId, t.createdByMemberId),
  sharedShortcutUnique: uniqueIndex('quick_replies_shared_shortcut_unique')
    .on(t.organizationId, sql`lower(${t.shortcut})`)
    .where(sql`${t.scope} = 'shared' and ${t.deletedAt} is null`),
  personalShortcutUnique: uniqueIndex('quick_replies_personal_shortcut_unique')
    .on(t.organizationId, t.createdByMemberId, sql`lower(${t.shortcut})`)
    .where(sql`${t.scope} = 'personal' and ${t.deletedAt} is null`),
}))

// Passos de uma resposta rápida em sequência (ex: áudio de apresentação + foto do
// produto, mandados em mensagens separadas com um único atalho). Uma quick_reply sem
// nenhuma linha aqui continua funcionando exatamente como antes — usa o próprio
// content/media_url dela como sequência implícita de 1 passo. Só resposta com steps
// de verdade ignora content/media_url do pai.
export const quickReplySteps = pgTable('quick_reply_steps', {
  id: uuid('id').defaultRandom().primaryKey(),
  quickReplyId: uuid('quick_reply_id').notNull().references(() => quickReplies.id, { onDelete: 'cascade' }),
  position: integer('position').notNull(),
  content: text('content').notNull().default(''),
  mediaUrl: text('media_url'),
  mediaType: text('media_type'),
  mediaMimetype: text('media_mimetype'),
  mediaFilename: text('media_filename'),
  // Espera (em segundos) depois de mandar este passo, antes do próximo — 0 = sem
  // pausa, sai um atrás do outro como sempre foi.
  delaySeconds: integer('delay_seconds').notNull().default(0),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  quickReplyPositionUnique: uniqueIndex('quick_reply_steps_position_unique').on(t.quickReplyId, t.position),
}))

// ── Histórico de Status do Pedido ──────────────────────────────────────────────
export const orderStatusHistory = pgTable('order_status_history', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  orderId: uuid('order_id').notNull().references(() => orders.id, { onDelete: 'cascade' }),
  field: text('field').notNull(),
  fromStatus: text('from_status'),
  toStatus: text('to_status').notNull(),
  changedByMemberId: uuid('changed_by_member_id'),
  changedAt: timestamp('changed_at', { withTimezone: true }).defaultNow(),
}, (t) => ({
  orderIdx: index('order_status_history_order_idx').on(t.orderId, t.changedAt),
}))

// ── Despesas / Contas a Pagar ──────────────────────────────────────────────────
export const expenses = pgTable('expenses', {
  id: uuid('id').defaultRandom().primaryKey(),
  organizationId: uuid('organization_id').notNull().references(() => organizations.id),
  description: text('description').notNull(),
  category: text('category').notNull().default('outros'),
  amount: numeric('amount', { precision: 15, scale: 2 }).notNull(),
  dueDate: timestamp('due_date', { withTimezone: true }).notNull(),
  status: text('status').notNull().default('pending'),
  paidAt: timestamp('paid_at', { withTimezone: true }),
  payee: text('payee'),
  notes: text('notes'),
  isRecurring: boolean('is_recurring').notNull().default(false),
  recurrenceInterval: text('recurrence_interval'),
  recurrenceDay: integer('recurrence_day'),
  recurrenceEndDate: timestamp('recurrence_end_date', { withTimezone: true }),
  parentExpenseId: uuid('parent_expense_id'),
  createdByMemberId: uuid('created_by_member_id'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
}, (t) => ({
  parentExpenseFk: foreignKey({ columns: [t.parentExpenseId], foreignColumns: [t.id] }).onDelete('set null'),
  orgDueDateIdx: index('expenses_org_due_date_idx').on(t.organizationId, t.dueDate),
  orgStatusIdx: index('expenses_org_status_idx').on(t.organizationId, t.status),
  parentDueDateUnique: uniqueIndex('expenses_parent_due_date_unique')
    .on(t.parentExpenseId, t.dueDate)
    .where(sql`${t.parentExpenseId} is not null and ${t.deletedAt} is null`),
}))

// ── Prints das funções (tela Início) ─────────────────────────────────────────
// Global, não por organização — são screenshots do próprio produto (Chat, Pipeline
// etc.), iguais pra qualquer tenant. Só o superadmin pode trocar (ver
// /api/platform/feature-screenshots); qualquer usuário autenticado só lê.
export const featureScreenshots = pgTable('feature_screenshots', {
  id: uuid('id').defaultRandom().primaryKey(),
  featureKey: text('feature_key').notNull().unique(),
  imageUrl: text('image_url').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow(),
})
