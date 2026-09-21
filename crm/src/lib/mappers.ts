import { leads } from '@/lib/schema'

type DrizzleLead = typeof leads.$inferSelect

export function mapLead(l: DrizzleLead) {
  return {
    id: l.id,
    organization_id: l.organizationId,
    stage_id: l.stageId,
    integration_id: l.integrationId,
    owner_member_id: l.ownerMemberId,
    title: l.title,
    external_id: l.externalId,
    email: l.email,
    phone: l.phone,
    avatar_url: l.avatarUrl,
    ai_interest_level: l.aiInterestLevel,
    ai_next_action_short: l.aiNextActionShort,
    custom_attributes: l.customAttributes,
    last_message_content: l.lastMessageContent,
    last_message_sender_type: l.lastMessageSenderType,
    last_activity_at: l.lastActivityAt,
    last_activity_type: l.lastActivityType,
    last_activity_by_member_id: l.lastActivityByMemberId,
    is_group: l.isGroup,
    is_unread: l.isUnread,
    is_pinned: l.isPinned,
    is_archived: l.isArchived,
    value: l.value,
    goals: l.goals,
    cep: l.cep,
    address: l.address,
    address_number: l.addressNumber,
    address_complement: l.addressComplement,
    neighborhood: l.neighborhood,
    city: l.city,
    state: l.state,
    created_at: l.createdAt,
    updated_at: l.updatedAt,
    deleted_at: l.deletedAt,
  }
}
