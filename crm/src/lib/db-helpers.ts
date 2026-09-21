/**
 * Helpers de query para Neon/Drizzle
 * Substitui padrões recorrentes do Supabase client
 *
 * Substitui:
 *   supabase.from('leads').select('*').eq('organization_id', orgId)
 *   → db.select().from(leads).where(eq(leads.organizationId, orgId))
 */
import { eq, and, isNull, desc, asc, sql } from 'drizzle-orm'
import { db } from './db'
import {
  leads, leadActivities, leadTags, tags, organizationMembers,
  profiles, pipelineStages, pipelines, integrations, organizationRoles,
  customFieldDefinitions, customFieldCategories, notifications, orderItems,
} from './schema'

// ── Concorrência ──────────────────────────────────────────────────────────────

/**
 * Código de erro padrão do Postgres pra violação de constraint única (23505). Usado
 * junto com as constraints em leads(organization_id, phone)/leads(integration_id,
 * external_id)/lead_activities(metadata->>'*_message_id') — quando duas requisições
 * concorrentes (ex: dois webhooks quase simultâneos) tentam criar o mesmo lead ou a
 * mesma mensagem, o banco garante que só uma vence a corrida; a outra pega esse erro
 * em vez de duplicar silenciosamente.
 */
export function isUniqueViolation(err: unknown): boolean {
  return !!err && typeof err === 'object' && (err as { code?: string }).code === '23505'
}

// ── Pedidos ───────────────────────────────────────────────────────────────────

export interface OrderAddressSync {
  cep?: string | null
  address?: string | null
  addressNumber?: string | null
  addressComplement?: string | null
  neighborhood?: string | null
  city?: string | null
  state?: string | null
}

/**
 * Espelha o último pedido no lead: status/forma de pagamento (etiqueta
 * "Pago/Pendente" da lista de conversas) e os nomes dos produtos comprados
 * (etiqueta de produto no card do Pipeline).
 *
 * Precisa ser chamado tanto na criação quanto em qualquer atualização do
 * payment_status de um pedido, senão as etiquetas ficam desatualizadas.
 *
 * Por que denormalizar em vez de fazer join na hora de listar: o Pipeline
 * carrega centenas de leads de uma vez e não passa perto da tabela de pedidos —
 * juntar orders + order_items pra cada card sairia caro pra mostrar um rótulo.
 * É o mesmo motivo (e o mesmo lugar) de last_order_payment_status.
 *
 * `orderId` faz a função buscar os itens do pedido sozinha, em vez de os
 * chamadores passarem a lista: são dois call sites (criar e atualizar pedido) e
 * o de atualizar nem sempre mexe nos itens, então deixar a leitura aqui é o que
 * garante que os dois gravem a mesma coisa.
 *
 * Quando `address` é passado, também grava o endereço nas colunas do lead
 * (cep/address/address_number/...) — assim o endereço do último pedido já
 * vem pronto pra pré-preencher a próxima compra do mesmo cliente.
 */
export async function syncLeadLastOrderAttributes(
  organizationId: string,
  leadId: string,
  paymentStatus: string,
  paymentMethod: string,
  address?: OrderAddressSync,
  orderId?: string
) {
  // Nomes dos produtos do pedido, sem repetir (um pedido pode ter o mesmo
  // produto em duas linhas). Sem orderId, mantém o que já estava gravado.
  let products: string[] | null = null
  if (orderId) {
    const rows = await db
      .select({ name: orderItems.productName })
      .from(orderItems)
      .where(eq(orderItems.orderId, orderId))
    products = [...new Set(rows.map((r) => r.name).filter(Boolean))]
  }

  const basePatch = sql`jsonb_set(
    jsonb_set(
      COALESCE(custom_attributes, '{}'),
      '{last_order_payment_status}', ${JSON.stringify(paymentStatus)}::jsonb
    ),
    '{last_order_payment_method}', ${JSON.stringify(paymentMethod)}::jsonb
  )`

  // Expressao montada por composicao (e nao com subquery/CTE) porque uma
  // subquery derivada no SET nao consegue enxergar custom_attributes da linha
  // que esta sendo atualizada sem LATERAL — jsonb_set aninhado le a coluna
  // direto e nao tem esse problema.
  const attributes = products
    ? sql`jsonb_set(${basePatch}, '{last_order_products}', ${JSON.stringify(products)}::jsonb)`
    : basePatch

  if (address) {
    await db.execute(sql`
      UPDATE leads
      SET custom_attributes = ${attributes},
      cep = ${address.cep ?? null},
      address = ${address.address ?? null},
      address_number = ${address.addressNumber ?? null},
      address_complement = ${address.addressComplement ?? null},
      neighborhood = ${address.neighborhood ?? null},
      city = ${address.city ?? null},
      state = ${address.state ?? null},
      updated_at = NOW()
      WHERE id = ${leadId} AND organization_id = ${organizationId}
    `)
    return
  }

  await db.execute(sql`
    UPDATE leads
    SET custom_attributes = ${attributes},
    updated_at = NOW()
    WHERE id = ${leadId} AND organization_id = ${organizationId}
  `)
}

// ── Leads ─────────────────────────────────────────────────────────────────────

export async function getLeadsWithOwner(organizationId: string, stageId?: string) {
  let query = db
    .select()
    .from(leads)
    .where(
      and(
        eq(leads.organizationId, organizationId),
        isNull(leads.deletedAt),
        stageId ? eq(leads.stageId, stageId) : undefined
      )
    )
    .orderBy(desc(leads.createdAt))

  return query
}

export async function getLeadById(organizationId: string, leadId: string) {
  const [lead] = await db
    .select()
    .from(leads)
    .where(
      and(
        eq(leads.id, leadId),
        eq(leads.organizationId, organizationId),
        isNull(leads.deletedAt)
      )
    )
    .limit(1)
  return lead || null
}

// ── Lead Activities ───────────────────────────────────────────────────────────

export async function getLeadActivities(organizationId: string, leadId: string) {
  return db
    .select({
      id: leadActivities.id,
      type: leadActivities.type,
      content: leadActivities.content,
      metadata: leadActivities.metadata,
      actorMemberId: leadActivities.actorMemberId,
      createdAt: leadActivities.createdAt,
      actor: {
        id: organizationMembers.id,
        fullName: profiles.fullName,
        avatarUrl: profiles.avatarUrl,
      },
    })
    .from(leadActivities)
    .leftJoin(organizationMembers, eq(organizationMembers.id, leadActivities.actorMemberId))
    .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
    .where(
      and(
        eq(leadActivities.organizationId, organizationId),
        eq(leadActivities.leadId, leadId)
      )
    )
    .orderBy(asc(leadActivities.createdAt))
}

// ── Organization Members ──────────────────────────────────────────────────────

export async function getMemberByUserId(organizationId: string, userId: string) {
  const [member] = await db
    .select({
      id: organizationMembers.id,
      organizationId: organizationMembers.organizationId,
      roleId: organizationMembers.roleId,
      status: organizationMembers.status,
      fullName: profiles.fullName,
      avatarUrl: profiles.avatarUrl,
    })
    .from(organizationMembers)
    .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
    .where(
      and(
        eq(organizationMembers.organizationId, organizationId),
        eq(organizationMembers.userId, userId),
        eq(organizationMembers.status, 'active')
      )
    )
    .limit(1)

  return member || null
}

// ── Pipelines ─────────────────────────────────────────────────────────────────

export async function getPipelinesWithStages(organizationId: string) {
  const pipelinesData = await db
    .select()
    .from(pipelines)
    .where(
      and(
        eq(pipelines.organizationId, organizationId),
        isNull(pipelines.deletedAt)
      )
    )
    .orderBy(asc(pipelines.createdAt))

  const stagesData = await db
    .select()
    .from(pipelineStages)
    .where(
      and(
        eq(pipelineStages.organizationId, organizationId),
        isNull(pipelineStages.deletedAt)
      )
    )
    .orderBy(asc(pipelineStages.rank))

  return pipelinesData.map((p) => ({
    ...p,
    stages: stagesData.filter((s) => s.pipelineId === p.id),
  }))
}
