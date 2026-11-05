import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired, validateSource } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import {
  leads, leadTags, tags, organizationMembers, profiles, pipelineStages, integrations,
} from '@/lib/schema'
import { eq, and, isNull, desc, asc, ilike, or, sql, count, inArray } from 'drizzle-orm'
import { mapLead } from '@/lib/mappers'
import { etapaInicialDaLinha } from '@/lib/etapaDaLinha'
import { linhaDoTipo, type LinhaWhatsapp } from '@/lib/leadChannel'
import { acharLeadDaLinha } from '@/lib/leadDaLinha'

/**
 * A aba em que esta conversa aparece: a da linha DO LEAD, e só ela.
 *
 * De 26/09 a 28/09 entravam também as linhas de todas as mensagens, para uma
 * conversa aparecer em mais de uma aba -- remendo do lead único por telefone,
 * que misturava as conversas (Tel, 28/09: "não misturando contatos"). Desde
 * `leadDaLinha.ts` cada lead é de uma linha.
 */
function linhasDe(tipoDaIntegracao: string | null, integrationId: string | null): LinhaWhatsapp[] {
  const doLead = linhaDoTipo(tipoDaIntegracao) ?? (integrationId && !tipoDaIntegracao ? 'parceria' : null)
  return doLead ? [doLead] : []
}
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
    /**
     * Só estas conversas (29/09, Pedro: "máximo de velocidade... cliques rápidos
     * sem bugar"). A tela recebe "a conversa X mudou" e busca só ela, em vez da
     * lista inteira (352 conversas, 400 KB) a cada mensagem.
     */
    const idsPedidos = (searchParams.get('ids') || '').split(',').map((s) => s.trim())
      .filter((s) => /^[0-9a-f-]{36}$/i.test(s)).slice(0, 100)

    const conditions = [
      eq(leads.organizationId, auth.organizationId),
      isNull(leads.deletedAt),
    ]

    if (q) {
      // A LUPA GERAL PROCURA POR "CONTÉM" (Pedro, 30/09: "só aparece quando eu digito o
      // número exato"). O número é comparado só pelos dígitos -- "(92) 99163", "92 9163"
      // e "991630597" acham o mesmo contato -- e pelos 8 finais, que não dependem do 9.
      const dig = q.replace(/\D/g, '')
      const pedacos = [dig, dig.length >= 8 ? dig.slice(-8) : ''].filter((x) => x.length >= 3)
      conditions.push(or(
        sql`translate(lower(coalesce(${leads.title}, '')), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') LIKE ${'%' + q.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '') + '%'}`,
        ilike(leads.email, `%${q}%`), ilike(leads.phone, `%${q}%`),
        ...pedacos.map((p) => sql`regexp_replace(coalesce(${leads.phone}, ''), '[^0-9]', '', 'g') LIKE ${'%' + p + '%'}`),
      )!)
    }
    if (phone) conditions.push(ilike(leads.phone, `%${phone}%`))
    if (assignedTo) conditions.push(eq(leads.ownerMemberId, assignedTo))
    if (owner) conditions.push(eq(leads.ownerMemberId, owner))
    if (stageId) conditions.push(eq(leads.stageId, stageId))
    if (excludeGroups) conditions.push(or(isNull(leads.isGroup), eq(leads.isGroup, false))!)
    if (searchParams.has('ids')) conditions.push(idsPedidos.length ? inArray(leads.id, idsPedidos) : sql`false`)
    // 04/11 (Pedro: "o de Leads não quero que carregue para a Rayssa, só se ela clicar"): só as conversas da Parceria e as
    // ENVIADAS para ela (Enviar para Rayssa, mudou_para), para quem só usa a Parceria
    if (searchParams.get('linha') === 'parceria') {
      conditions.push(sql`(${leads.integrationId} IN (SELECT id FROM integrations WHERE type = 'whatsapp_zapi')
        OR ${leads.customAttributes}->>'mudou_para' = 'parceria')`)
    }
    // 05/11 (Pedro: "carregar as conversas só dos últimos 7 dias inicialmente"): a primeira carga da tela vem só com quem se
    // mexeu nesses dias (e as fixadas e não lidas); a lista inteira vem logo depois (LeadsContext)
    const dias = Number(searchParams.get('dias'))
    if (Number.isInteger(dias) && dias > 0 && dias <= 365) {
      conditions.push(sql`(coalesce(${leads.lastActivityAt}, ${leads.createdAt}) > now() - make_interval(days => ${dias}::int)
        OR ${leads.isPinned} IS TRUE OR ${leads.isUnread} IS TRUE)`)
    }

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
    const atendimento: Record<string, { autores: string[]; humano: boolean; ultimaDoLead: string | null; ultimaDeGente: string | null }> = {}
    if (scope === 'conversas' && leadIds.length > 0) {
      // Mensagem de robô (funil, automação, agente de IA) não é atendimento.
      const manual = sql`(
        a.metadata->>'direction' = 'outbound'
        AND coalesce(a.metadata->>'automated', 'false') <> 'true'
        AND coalesce(a.metadata->>'source', '') NOT IN ('funnel', 'ai', 'ai_agent', 'automation')
      )`
      /* VELOCIDADE (Pedro, 29/10: "tá lento de carregar as conversas no CRM, dá uma otimizada sem bugar nada"): era uma
         consulta só, com o array_agg ORDENADO sobre as ~75 mil mensagens -- o Postgres ordenava tudo (30 MB em disco,
         ~3,8 s). Agora são duas, ao mesmo tempo: as contas por conversa (sem ordenar) e os autores, ordenados só nas
         mensagens escritas por alguém do time. Mesma resposta: conferida linha a linha contra a de antes (0 diferenças). */
      const ids = sql.raw(`ARRAY['${leadIds.join("','")}']::uuid[]`)
      const [linhas, quem] = await Promise.all([
        db.execute(sql`
          SELECT a.lead_id,
            bool_or(${manual}) AS teve_manual,
            min(a.created_at) FILTER (WHERE a.metadata->>'automated' = 'true' OR a.metadata->>'source' = 'funnel') AS primeira_automatica,
            max(a.created_at) FILTER (WHERE a.metadata->>'direction' = 'inbound') AS ultima_do_lead,
            max(a.created_at) FILTER (WHERE ${manual}) AS ultima_manual
          FROM lead_activities a
          WHERE a.organization_id = ${auth.organizationId}
            AND a.lead_id = ANY(${ids})
            AND a.metadata->>'direction' IS NOT NULL
          GROUP BY a.lead_id
        `),
        // Todos os autores, do mais recente pro mais antigo: quem é do time
        // de atendimento decide a tela (a conta de admin não vira etiqueta).
        // O × da etiqueta Tel/Rayssa (pessoa_solta_em) zera a conta: quem
        // escreveu pelo login ANTES dele não prende mais a conversa na aba.
        db.execute(sql`
          SELECT a.lead_id, array_agg(a.actor_member_id ORDER BY a.created_at DESC) AS autores
          FROM lead_activities a
          LEFT JOIN leads ld ON ld.id = a.lead_id
          WHERE a.organization_id = ${auth.organizationId}
            AND a.lead_id = ANY(${ids})
            AND a.actor_member_id IS NOT NULL AND ${manual}
            AND a.created_at > coalesce(nullif(ld.custom_attributes->>'pessoa_solta_em', '')::timestamptz, '-infinity'::timestamptz)
          GROUP BY a.lead_id
        `),
      ])
      const autoresDe = new Map((quem.rows as { lead_id: string; autores: string[] | null }[]).map((q) => [q.lead_id, q.autores]))
      for (const l0 of linhas.rows as {
        lead_id: string; teve_manual: boolean | null
        primeira_automatica: string | null; ultima_do_lead: string | null; ultima_manual: string | null
      }[]) {
        const l = { ...l0, autores: autoresDe.get(l0.lead_id) ?? null }
        // a última vez que GENTE falou na conversa: a pessoa ou alguém do time (disparo e Nay não contam)
        const deGente = Math.max(l.ultima_do_lead ? new Date(l.ultima_do_lead).getTime() : 0,
                                 l.ultima_manual ? new Date(l.ultima_manual).getTime() : 0)
        const respondeuAutomacao = !!l.primeira_automatica && !!l.ultima_do_lead &&
          new Date(l.ultima_do_lead) > new Date(l.primeira_automatica)
        atendimento[l.lead_id] = {
          autores: [...new Set(l.autores ?? [])],
          humano: !!l.teve_manual || respondeuAutomacao,
          ultimaDoLead: l.ultima_do_lead ? new Date(l.ultima_do_lead).toISOString() : null,
          ultimaDeGente: deGente ? new Date(deGente).toISOString() : null,
        }
      }
    }

    /* QUANTAS MENSAGENS ESTÃO SEM LER (Pedro, 01/10/2026: "as bolinhas nas
       etapas do WhatsApp Parceria seja a contagem real de mensagens não
       lidas"). O CRM guarda só `is_unread` por conversa, não o estado de cada
       mensagem -- então a contagem é a das mensagens DELA depois da nossa
       última resposta, que é o que o WhatsApp mostra no balãozinho.
       Só para as conversas marcadas como não lidas: hoje são 2 na Parceria,
       então isto não pesa na lista. */
    const naoLidas: Record<string, number> = {}
    const idsNaoLidos = rows.filter((r) => r.lead.isUnread).map((r) => r.lead.id)
    if (idsNaoLidos.length > 0) {
      // 29/10 (velocidade): a "última resposta nossa" era procurada de novo para CADA mensagem recebida (1.315 vezes,
      // ~7-9 s); agora sai uma vez por conversa e a conta é a mesma (conferida: 0 diferenças, ~0,25 s)
      const naoIds = sql.raw(`ARRAY['${idsNaoLidos.join("','")}']::uuid[]`)
      const contagem = await db.execute(sql`
        WITH ult AS (
          SELECT a.lead_id, max(a.created_at) FILTER (WHERE a.metadata->>'direction' = 'outbound') AS nossa
            FROM lead_activities a
           WHERE a.lead_id = ANY(${naoIds})
           GROUP BY a.lead_id)
        SELECT a.lead_id, count(*)::int AS n
          FROM lead_activities a
          JOIN ult u ON u.lead_id = a.lead_id
         WHERE a.organization_id = ${auth.organizationId}
           AND a.lead_id = ANY(${naoIds})
           AND a.metadata->>'direction' = 'inbound'
           AND a.created_at > coalesce(u.nossa, '-infinity'::timestamptz)
         GROUP BY a.lead_id`)
      for (const l of contagem.rows as Array<{ lead_id: string; n: number }>) naoLidas[l.lead_id] = Number(l.n) || 0
    }

    const result = rows.map((r) => ({
      ...mapLead(r.lead),
      // a conversa marcada à mão como não lida, sem mensagem nova dela, conta 1
      nao_lidas: r.lead.isUnread ? (naoLidas[r.lead.id] || 1) : 0,
      // Grupo não é atendimento de lead: fica fora das etiquetas e da aba Humano.
      ...(scope === 'conversas' && {
        autores_manuais: r.lead.isGroup ? [] : atendimento[r.lead.id]?.autores ?? [],
        em_atendimento_humano: r.lead.isGroup ? false : atendimento[r.lead.id]?.humano ?? false,
        // quando a PESSOA escreveu por último: a aba Oficial ordena por isto (o disparo não conta)
        ultima_recebida: atendimento[r.lead.id]?.ultimaDoLead ?? null,
        // a última mensagem da pessoa OU de alguém do time: a ordem da aba Oficial (13/10)
        ultima_de_gente: atendimento[r.lead.id]?.ultimaDeGente ?? null,
      }),
      lead_tags: tagsMap[r.lead.id] || [],
      integration: r.integrationType ? ({ type: r.integrationType } as Integration) : undefined,
      linhas: linhasDe(r.integrationType, r.lead.integrationId),
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

    // Verifica duplicata por telefone NA MESMA LINHA (28/09): a mesma pessoa
    // pode ter uma conversa em cada número, e cadastrar na Parceria alguém que
    // já fala com a captação é um lead novo, não o de lá.
    if (body.phone) {
      const existing = await acharLeadDaLinha(auth.organizationId, [body.phone], body.integration_id || null)
      if (existing) return Response.json({ data: { id: existing.id }, existed: true })
    }

    /* A ETAPA SAI DO PIPELINE DA LINHA (Tel, 26/09/2026: "vai ter essa divisão no
       pipeline cada pipeline para cada zap").

       Antes daqui saía "a primeira etapa da organização", sem olhar pipeline.
       Com dois pipelines, os dois têm etapa de rank 1 -- "Contactando" na
       captação e "Agendou visita" na parceria -- e o banco devolvia qualquer uma
       das duas. Um corretor da parceria podia nascer dentro do pipeline da
       captação, e ninguém notaria olhando a tela. */
    let tipoDaLinha: string | null = null
    if (body.integration_id) {
      const [integ] = await db.select({ type: integrations.type }).from(integrations)
        .where(and(eq(integrations.id, body.integration_id), isNull(integrations.deletedAt))).limit(1)
      tipoDaLinha = integ?.type ?? null
    }
    const etapaDaLinha = await etapaInicialDaLinha(auth.organizationId, tipoDaLinha)

    let lead: typeof leads.$inferSelect
    try {
      ;[lead] = await db
        .insert(leads)
        .values({
          organizationId: auth.organizationId,
          title: body.title,
          phone: body.phone || null,
          email: body.email || null,
          stageId: body.stage_id || etapaDaLinha || null,
          ownerMemberId: body.owner_member_id || null,
          /*
           * DE QUAL LINHA DE WHATSAPP É O LEAD (Tel, 26/09/2026).
           *
           * Sem isto o lead cadastrado à mão não aparece em nenhuma das duas
           * abas do chat: elas filtram pelo tipo da integração, e um lead sem
           * integração não é de linha nenhuma.
           */
          integrationId: body.integration_id || null,
          customAttributes: body.custom_fields || {},
          lastActivityAt: new Date(),
        })
        .returning()
    } catch (err) {
      // Checagem de duplicata acima (linha ~113) não cobre corrida entre duas
      // requisições simultâneas — leads_org_phone_unique garante isso no banco.
      if (!isUniqueViolation(err) || !body.phone) throw err
      const raceLead = await acharLeadDaLinha(auth.organizationId, [body.phone], body.integration_id || null)
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
