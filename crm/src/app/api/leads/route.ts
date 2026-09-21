import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired, validateSource } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import {
  leads, leadTags, tags, organizationMembers, profiles, pipelineStages, integrations,
} from '@/lib/schema'
import { eq, and, isNull, desc, asc, ilike, or, sql, count } from 'drizzle-orm'
import { mapLead } from '@/lib/mappers'
import { isUniqueViolation } from '@/lib/db-helpers'
import type { Integration } from '@/lib/types'
import { DIAS_CONVERSA_IMPORTADA } from '@/lib/conversas'

/**
 * GET /api/leads
 * Lista leads com paginação, filtros e busca
 */
export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const { searchParams } = new URL(req.url)

    const page = parseInt(searchParams.get('page') || '1')
    const limit = Math.min(parseInt(searchParams.get('limit') || '20'), 100)
    const q = searchParams.get('q')
    const phone = searchParams.get('phone')
    const assignedTo = searchParams.get('assigned_to')
    const returnAll = searchParams.get('returnAll') === 'true'
    const stageId = searchParams.get('stage_id')
    const excludeGroups = searchParams.get('exclude_groups') === 'true'
    const owner = searchParams.get('owner')
    /**
     * Recorte por tela. Sem ele, Chat e Pipeline baixavam a base inteira —
     * 2.366 linhas pra desenhar 82 conversas ou 22 cards.
     *
     *   conversas → o que a lista do Chat mostra
     *   funil     → o que o Kanban desenha (card sem etapa não existe lá)
     */
    const scope = searchParams.get('scope')

    const conditions = [
      eq(leads.organizationId, auth.organizationId),
      isNull(leads.deletedAt),
    ]

    if (q) conditions.push(or(ilike(leads.title, `%${q}%`), ilike(leads.email, `%${q}%`), ilike(leads.phone, `%${q}%`))!)
    if (phone) conditions.push(ilike(leads.phone, `%${phone}%`))
    if (assignedTo) conditions.push(eq(leads.ownerMemberId, assignedTo))
    if (owner) conditions.push(eq(leads.ownerMemberId, owner))
    if (stageId) conditions.push(eq(leads.stageId, stageId))
    if (excludeGroups) conditions.push(or(isNull(leads.isGroup), eq(leads.isGroup, false))!)

    if (scope === 'funil') {
      conditions.push(sql`${leads.stageId} IS NOT NULL`)
    } else if (scope === 'conversas') {
      // Conversa é quem já teve atividade. Dentro disso: mensagem registrada
      // aqui aparece pra sempre; conversa importada sem mensagem só enquanto for
      // recente; arquivada vem sempre, senão a aba "Arquivados" fica vazia.
      conditions.push(sql`(
        ${leads.lastMessageContent} IS NOT NULL
        OR ${leads.lastMessageSenderType} IS NOT NULL
        OR ${leads.isArchived} IS TRUE
        OR (
          ${leads.lastActivityType} IS NOT NULL
          AND ${leads.lastActivityAt} > now() - (${DIAS_CONVERSA_IMPORTADA} || ' days')::interval
        )
      )`)
    }

    const offset = (page - 1) * limit

    const query = db
      .select({
        lead: leads,
        integrationType: integrations.type,
        ownerMemberIdJoin: organizationMembers.id,
        ownerFullName: profiles.fullName,
        ownerAvatarUrl: profiles.avatarUrl,
      })
      .from(leads)
      .leftJoin(integrations, eq(integrations.id, leads.integrationId))
      .leftJoin(organizationMembers, eq(organizationMembers.id, leads.ownerMemberId))
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .where(and(...conditions))
      .orderBy(desc(sql`coalesce(${leads.lastActivityAt}, ${leads.createdAt})`))

    const rows = returnAll ? await query : await query.limit(limit).offset(offset)
    const data = rows.map((r) => r.lead)

    // Buscar tags para cada lead
    const leadIds = data.map((l) => l.id)
    let tagsMap: Record<string, any[]> = {}
    if (leadIds.length > 0) {
      const tagsData = await db
        .select({
          leadId: leadTags.leadId,
          tagId: leadTags.tagId,
          name: tags.name,
          color: tags.color,
        })
        .from(leadTags)
        .leftJoin(tags, eq(tags.id, leadTags.tagId))
        .where(sql`${leadTags.leadId} = ANY(${sql.raw(`ARRAY['${leadIds.join("','")}']::uuid[]`)})`)

      for (const t of tagsData) {
        if (!tagsMap[t.leadId]) tagsMap[t.leadId] = []
        tagsMap[t.leadId].push({ tag_id: t.tagId, tag: { id: t.tagId, name: t.name, color: t.color } })
      }
    }

    // Atendimento (etiqueta de quem está atendendo + aba "Humano"). Calculado das
    // mensagens a cada leitura, nunca gravado — ver src/lib/atendentes.ts. Só na
    // lista do Chat, que é a única tela que mostra.
    const atendimento: Record<string, { autores: string[]; humano: boolean }> = {}
    if (scope === 'conversas' && leadIds.length > 0) {
      // Mensagem de robô (funil, automação, agente de IA) não é atendimento.
      const manual = sql`(
        a.metadata->>'direction' = 'outbound'
        AND coalesce(a.metadata->>'automated', 'false') <> 'true'
        AND coalesce(a.metadata->>'source', '') NOT IN ('funnel', 'ai', 'ai_agent', 'automation')
      )`
      const linhas = await db.execute(sql`
        SELECT a.lead_id,
          -- Todos os autores, do mais recente pro mais antigo: quem é do time
          -- de atendimento decide a tela (a conta de admin não vira etiqueta).
          array_agg(a.actor_member_id ORDER BY a.created_at DESC)
            FILTER (WHERE a.actor_member_id IS NOT NULL AND ${manual}) AS autores,
          bool_or(${manual}) AS teve_manual,
          min(a.created_at) FILTER (WHERE a.metadata->>'automated' = 'true' OR a.metadata->>'source' = 'funnel') AS primeira_automatica,
          max(a.created_at) FILTER (WHERE a.metadata->>'direction' = 'inbound') AS ultima_do_lead
        FROM lead_activities a
        WHERE a.organization_id = ${auth.organizationId}
          AND a.lead_id = ANY(${sql.raw(`ARRAY['${leadIds.join("','")}']::uuid[]`)})
          AND a.metadata->>'direction' IS NOT NULL
        GROUP BY a.lead_id
      `)
      for (const l of linhas.rows as {
        lead_id: string; autores: string[] | null; teve_manual: boolean | null
        primeira_automatica: string | null; ultima_do_lead: string | null
      }[]) {
        const respondeuAutomacao = !!l.primeira_automatica && !!l.ultima_do_lead &&
          new Date(l.ultima_do_lead) > new Date(l.primeira_automatica)
        atendimento[l.lead_id] = {
          autores: [...new Set(l.autores ?? [])],
          humano: !!l.teve_manual || respondeuAutomacao,
        }
      }
    }

    const result = rows.map((r) => ({
      ...mapLead(r.lead),
      // Grupo não é atendimento de lead: fica fora das etiquetas e da aba Humano.
      ...(scope === 'conversas' && {
        autores_manuais: r.lead.isGroup ? [] : atendimento[r.lead.id]?.autores ?? [],
        em_atendimento_humano: r.lead.isGroup ? false : atendimento[r.lead.id]?.humano ?? false,
      }),
      lead_tags: tagsMap[r.lead.id] || [],
      integration: r.integrationType ? ({ type: r.integrationType } as Integration) : undefined,
      owner: r.ownerMemberIdJoin
        ? { id: r.ownerMemberIdJoin, profiles: { full_name: r.ownerFullName || '', avatar_url: r.ownerAvatarUrl || undefined } }
        : undefined,
    }))

    return Response.json({ data: result, page, limit })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * POST /api/leads
 * Cria um novo lead
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    const requiredError = validateRequired(body, ['title', 'source'])
    if (requiredError) return apiError(400, requiredError)

    // Verifica duplicata por telefone
    if (body.phone) {
      const [existing] = await db
        .select({ id: leads.id })
        .from(leads)
        .where(
          and(
            eq(leads.organizationId, auth.organizationId),
            eq(leads.phone, body.phone),
            isNull(leads.deletedAt)
          )
        )
        .limit(1)

      if (existing) return Response.json({ data: existing, existed: true })
    }

    const [firstStage] = await db
      .select({ id: pipelineStages.id })
      .from(pipelineStages)
      .where(
        and(
          eq(pipelineStages.organizationId, auth.organizationId),
          isNull(pipelineStages.deletedAt)
        )
      )
      .orderBy(asc(pipelineStages.rank))
      .limit(1)

    let lead: typeof leads.$inferSelect
    try {
      ;[lead] = await db
        .insert(leads)
        .values({
          organizationId: auth.organizationId,
          title: body.title,
          phone: body.phone || null,
          email: body.email || null,
          stageId: body.stage_id || firstStage?.id || null,
          ownerMemberId: body.owner_member_id || null,
          customAttributes: body.custom_fields || {},
          lastActivityAt: new Date(),
        })
        .returning()
    } catch (err) {
      // Checagem de duplicata acima (linha ~113) não cobre corrida entre duas
      // requisições simultâneas — leads_org_phone_unique garante isso no banco.
      if (!isUniqueViolation(err) || !body.phone) throw err
      const [raceLead] = await db.select().from(leads)
        .where(and(eq(leads.organizationId, auth.organizationId), eq(leads.phone, body.phone), isNull(leads.deletedAt)))
        .limit(1)
      if (!raceLead) throw err
      return Response.json({ data: raceLead, existed: true })
    }

    // Aplicar tags se enviadas
    if (body.tags && Array.isArray(body.tags) && body.tags.length > 0) {
      await db.insert(leadTags).values(
        body.tags.map((tagId: string) => ({
          leadId: lead.id,
          tagId,
          organizationId: auth.organizationId,
        }))
      ).onConflictDoNothing()
    }

    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_CREATED, { id: lead.id })

    return Response.json({ data: lead }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
