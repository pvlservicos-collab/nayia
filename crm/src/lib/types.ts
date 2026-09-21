// Organization
export interface Organization {
  id: string
  name: string
  tier_id?: string
  timezone?: string
  logo_url?: string
  corporate_email?: string
  phone?: string
  website?: string
  foundation_date?: string
  created_at: string
  updated_at: string
}

// Pipeline
export interface Pipeline {
  id: string
  organization_id: string
  name: string
  settings?: any
  created_at: string
  updated_at: string
}

export interface PipelineStage {
  id: string
  organization_id?: string
  pipeline_id: string
  name: string
  color?: string
  rank: number
  target_volume?: number
  created_at: string
}

// Integration
export interface Integration {
  id: string
  organization_id: string
  name: string
  type: string
  status: 'active' | 'disabled'
  created_at: string
}

// Lead
export interface Lead {
  id: string
  organization_id: string
  stage_id: string
  integration_id?: string
  title: string
  email?: string
  phone?: string
  value?: number
  ai_interest_level: string
  ai_next_action_short?: string
  owner_member_id: string
  last_activity_at?: string
  last_activity_type?: string
  last_message_content?: string
  last_message_sender_type?: 'lead' | 'ai' | 'ai_agent' | 'human' | 'system_other'
  is_unread?: boolean
  is_pinned?: boolean
  is_archived?: boolean
  is_group?: boolean
  avatar_url?: string
  /**
   * Atendimento — calculado na hora pela lista de conversas (GET /api/leads),
   * a partir das mensagens; não é coluna, nada é gravado. Ver src/lib/atendentes.ts.
   *   autores_manuais       quem mandou mensagem manual pelo CRM, do mais
   *                         recente pro mais antigo (sem repetir)
   *   em_atendimento_humano a conversa está com o time (alguém respondeu à mão,
   *                         ou o lead respondeu a mensagem automática)
   */
  autores_manuais?: string[]
  em_atendimento_humano?: boolean
  custom_attributes?: Record<string, any>
  // Endereço salvo do cliente — preenchido a partir do último pedido com
  // endereço informado, pra já vir pronto em compras futuras.
  cep?: string
  address?: string
  address_number?: string
  address_complement?: string
  neighborhood?: string
  city?: string
  state?: string
  created_at: string
  updated_at: string
}

export interface LeadWithOwner extends Lead {
  owner?: {
    id: string
    profiles?: {
      full_name: string
      avatar_url?: string
    }
  }
  stage?: PipelineStage
  integration?: Integration
  lead_tags?: Array<{
    tag_id: string
    tag: { id: string; name: string; color: string }
  }>
}

export interface ChatMetadata {
  message_id?: string
  direction?: 'inbound' | 'outbound'
  source?: 'human' | 'ai' | 'ai_agent' | 'automation' | 'custom_field' | 'system' | 'rename' | 'evolution'
  status?: 'sent' | 'delivered' | 'read' | 'failed'
  sender_name?: string
  media_url?: string
  media_type?: 'image' | 'video' | 'audio' | 'document' | 'sticker'
  media_mimetype?: string
  media_filename?: string
  [key: string]: any
}

// Activities
export interface LeadActivity {
  id: string
  organization_id: string
  lead_id: string
  actor_member_id: string | null
  type: 'whatsapp' | 'note' | 'call' | 'email' | 'system'
  content: string
  metadata?: ChatMetadata
  created_at: string
}

export interface LeadActivityWithActor extends LeadActivity {
  actor?: {
    profiles?: {
      full_name: string
      avatar_url?: string
    }
  }
}

// Pinned messages
export interface PinnedMessage {
  id: string
  activity_id: string
  pinned_by_member_id: string | null
  pinned_at: string
  activity: LeadActivityWithActor
}

// Tags
export interface Tag {
  id: string
  organization_id: string
  name: string
  color: string
  created_at: string
}

// Custom Fields
export interface CustomFieldCategory {
  id: string
  organization_id: string
  name: string
  rank: number
  created_at: string
  updated_at: string
}

export interface CustomFieldDefinition {
  id: string
  organization_id: string
  category_id?: string
  key: string
  name: string
  field_type: 'text' | 'number' | 'currency' | 'date' | 'datetime' | 'bool' | 'select' | 'multi_select' | 'json'
  schema?: Record<string, any>
  is_indexed: boolean
  rank: number
  created_at: string
  updated_at: string
  deleted_at?: string
}

export interface CustomFieldIndexValue {
  id: string
  organization_id: string
  lead_id: string
  field_id: string
  value_text?: string
  value_number?: number
  value_date?: string
  value_bool?: boolean
  value_json?: Record<string, any>
  updated_at: string
  field_definition?: CustomFieldDefinition
}

// Member
export interface OrganizationMember {
  id: string
  organization_id: string
  user_id: string
  role_id: string
  status: string
  created_at: string
  profiles?: {
    full_name: string
    avatar_url?: string
  }
}

export interface OrganizationMemberWithProfile extends OrganizationMember {
  profiles: {
    full_name: string
    avatar_url?: string
  }
}

// Stage History
export interface LeadStageHistory {
  id: string
  organization_id: string
  lead_id: string
  from_stage_id: string | null
  to_stage_id: string | null
  changed_by_member_id: string | null
  changed_at: string
}

// AI Insights
export interface LeadAIInsights {
  id: string
  organization_id: string
  lead_id: string
  ai_summary?: string
  ai_metadata?: Record<string, any>
  updated_at: string
}

// Stage Goals
export interface StageGoal {
  id: string
  organization_id: string
  stage_id: string
  lead_count_goal: number
  value_goal: number
  created_at: string
  updated_at: string
}

// Lead search types — used by useLeadSearch, /api/leads/search, LeadList, LeadListItem.
export type LeadMatchType = 'title' | 'email' | 'phone' | 'message'

export interface SearchHit {
  lead: LeadWithOwner
  matchType: LeadMatchType
  snippet?: string
  matchedAt?: string // ISO
}

// Notifications
export interface Notification {
  id: string
  organization_id: string
  recipient_member_id: string
  actor_member_id?: string
  type?: string
  title?: string
  content?: string
  link_url?: string
  is_read: boolean
  created_at: string
  actor?: {
    profiles?: {
      full_name: string
      avatar_url?: string
    }
  }
}
