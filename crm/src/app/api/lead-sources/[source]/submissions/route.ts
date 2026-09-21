/**
 * GET  /api/lead-sources/{source}/submissions — linhas da planilha de uma aba.
 * POST /api/lead-sources/{source}/submissions — marca uma linha como contatada.
 *
 * O GET junta a etapa do lead no pipeline (o filtro por etapa da tela precisa
 * dela) e devolve, junto, a contagem por etapa — assim os chips de filtro já
 * nascem enumerados sem uma segunda requisição.
 *
 * Paginado por limit/offset: é um log, cresce sem teto.
 */
import { NextRequest } from 'next/server'
import { and, desc, eq, ilike, isNull, or, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadSourceSubmissions, leads, pipelineStages } from '@/lib/schema'
import { getLeadSource, LEAD_SOURCE_ORDER } from '@/lib/leadSources'

const DEFAULT_LIMIT = 100
const MAX_LIMIT = 500

/** Valor de `stage` que pede só as linhas sem etapa (sem lead no CRM). */
const SEM_ETAPA = 'sem_etapa'
/** Chip "Sem momento": lead que ainda não tem essa informação. */
const SEM_MOMENTO = 'sem_momento'

export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ source: string }> }
) {
  try {
    const auth = await authenticateRequest(req)
    const { source } = await params

    const sourceDef = getLeadSource(source)
    if (!sourceDef) {
      return apiError(404, `Fonte desconhecida: "${source}". Válidas: ${LEAD_SOURCE_ORDER.join(', ')}.`)
    }

    const url = req.nextUrl
    const limit = Math.min(Number(url.searchParams.get('limit')) || DEFAULT_LIMIT, MAX_LIMIT)
    const offset = Math.max(Number(url.searchParams.get('offset')) || 0, 0)
    const q = url.searchParams.get('q')?.trim()
    const stage = url.searchParams.get('stage')?.trim()
    // `contatados=nao` deixa à vista só quem ainda falta abordar.
    const contatados = url.searchParams.get('contatados')?.trim()

    const base = [
      eq(leadSourceSubmissions.organizationId, auth.organizationId),
      eq(leadSourceSubmissions.source, sourceDef.key),
    ]

    const filtros = [...base]
    if (q) {
      const like = `%${q}%`
      /*
       * Busca que ignora acento e formatação do telefone.
       *
       * Antes era ILIKE puro: procurar "João" não achava "Joao" (e vice-versa),
       * e "(11) 91234-5678" não achava 5511912345678 — os dois casos acontecem
       * o tempo todo, porque o nome vem digitado pela pessoa e o telefone é
       * guardado só com dígitos. `translate` resolve sem depender da extensão
       * unaccent, que não está instalada neste banco.
       */
      const semAcento = (coluna: any) => sql`translate(lower(${coluna}),
        'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ',
        'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN')`
      const alvo = sql`${semAcento(sql`${q}`)}`
      const digitos = q.replace(/\D/g, '')

      const condicoes = [
        sql`${semAcento(leadSourceSubmissions.name)} LIKE '%' || ${alvo} || '%'`,
        ilike(leadSourceSubmissions.email, like),
        ilike(leadSourceSubmissions.phone, like),
        ilike(leadSourceSubmissions.instagram, like),
        ilike(leadSourceSubmissions.externalId, like),
      ]
      if (digitos.length >= 4) {
        condicoes.push(sql`regexp_replace(coalesce(${leadSourceSubmissions.phone}, ''), '\D', '', 'g') LIKE ${'%' + digitos + '%'}`)
      }
      const match = or(...condicoes)
      if (match) filtros.push(match)
    }
    /*
     * Momento da jornada (src/lib/momentos.ts) — "só se cadastrou", "gerou a
     * agenda", os dois da mentoria. Sai do lead, e não do payload da submissão,
     * porque é lá que ele fica atualizado: a Agenda reenvia o mesmo lead quando
     * o quiz avança, e o cadastro manual do Pipeline também escreve ali.
     */
    const momentoDoLead = sql`coalesce(${leads.customAttributes}->>'phase', ${leads.customAttributes}->>'fase')`
    const momento = url.searchParams.get('momento')?.trim()
    if (momento === SEM_MOMENTO) filtros.push(sql`${momentoDoLead} IS NULL`)
    else if (momento) filtros.push(sql`${momentoDoLead} = ${momento}`)

    if (stage === SEM_ETAPA) filtros.push(isNull(leads.stageId))
    else if (stage) filtros.push(eq(leads.stageId, stage))
    if (contatados === 'nao') filtros.push(isNull(leadSourceSubmissions.contactedAt))
    else if (contatados === 'sim') filtros.push(sql`${leadSourceSubmissions.contactedAt} IS NOT NULL`)

    const where = and(...filtros)

    const [rows, [{ total }], porEtapa] = await Promise.all([
      db
        .select({
          id: leadSourceSubmissions.id,
          external_id: leadSourceSubmissions.externalId,
          name: leadSourceSubmissions.name,
          email: leadSourceSubmissions.email,
          phone: leadSourceSubmissions.phone,
          instagram: leadSourceSubmissions.instagram,
          payload: leadSourceSubmissions.payload,
          lead_id: leadSourceSubmissions.leadId,
          contacted_at: leadSourceSubmissions.contactedAt,
          received_at: leadSourceSubmissions.receivedAt,
          updated_at: leadSourceSubmissions.updatedAt,
          stage_id: leads.stageId,
          stage_name: pipelineStages.name,
          stage_color: pipelineStages.color,
        })
        .from(leadSourceSubmissions)
        .leftJoin(leads, eq(leads.id, leadSourceSubmissions.leadId))
        .leftJoin(pipelineStages, eq(pipelineStages.id, leads.stageId))
        .where(where)
        .orderBy(desc(leadSourceSubmissions.receivedAt))
        .limit(limit)
        .offset(offset),

      db
        .select({ total: sql<number>`count(*)::int` })
        .from(leadSourceSubmissions)
        .leftJoin(leads, eq(leads.id, leadSourceSubmissions.leadId))
        .where(where),

      // Contagem por etapa — NÃO aplica o filtro de etapa, senão o chip
      // selecionado zeraria os outros e não daria pra trocar de filtro.
      db
        .select({
          stage_id: leads.stageId,
          stage_name: pipelineStages.name,
          stage_color: pipelineStages.color,
          rank: pipelineStages.rank,
          total: sql<number>`count(*)::int`,
        })
        .from(leadSourceSubmissions)
        .leftJoin(leads, eq(leads.id, leadSourceSubmissions.leadId))
        .leftJoin(pipelineStages, eq(pipelineStages.id, leads.stageId))
        .where(and(...base))
        .groupBy(leads.stageId, pipelineStages.name, pipelineStages.color, pipelineStages.rank)
        .orderBy(pipelineStages.rank),
    ])

    // Contagem por momento — como a das etapas, sem aplicar o próprio filtro,
    // senão o chip escolhido zeraria os outros e não daria pra trocar.
    const porMomento = await db
      .select({ momento: momentoDoLead, total: sql<number>`count(*)::int` })
      .from(leadSourceSubmissions)
      .leftJoin(leads, eq(leads.id, leadSourceSubmissions.leadId))
      .where(and(...base))
      .groupBy(momentoDoLead)

    const [contagens] = await db
      .select({
        contatados: sql<number>`count(*) filter (where ${leadSourceSubmissions.contactedAt} is not null)::int`,
        pendentes: sql<number>`count(*) filter (where ${leadSourceSubmissions.contactedAt} is null)::int`,
      })
      .from(leadSourceSubmissions)
      .where(and(...base))

    return Response.json({
      data: rows,
      total,
      limit,
      offset,
      etapas: porEtapa.map((e) => ({
        id: e.stage_id ?? SEM_ETAPA,
        name: e.stage_name ?? 'Sem etapa',
        color: e.stage_color ?? null,
        total: e.total,
      })),
      momentos: porMomento.map((m) => ({ key: m.momento ?? SEM_MOMENTO, total: m.total })),
      contato: contagens ?? { contatados: 0, pendentes: 0 },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[submissions] GET falhou:', err)
    return apiError(500, 'Erro ao carregar os leads.')
  }
}

/**
 * Marca a linha como contatada. Idempotente: se já estava marcada, mantém a
 * data original — o registro é de quando o contato aconteceu pela primeira vez,
 * e reescrever isso apagaria a informação.
 */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ source: string }> }
) {
  try {
    const auth = await authenticateRequest(req)
    const { source } = await params
    if (!getLeadSource(source)) return apiError(404, `Fonte desconhecida: "${source}".`)

    const body = await req.json().catch(() => null)
    const id = body?.id
    if (!id || typeof id !== 'string') return apiError(400, 'Campo obrigatório: id.')

    const [linha] = await db
      .update(leadSourceSubmissions)
      .set({
        contactedAt: new Date(),
        contactedByMemberId: auth.memberId ?? null,
      })
      .where(and(
        eq(leadSourceSubmissions.id, id),
        eq(leadSourceSubmissions.organizationId, auth.organizationId),
        eq(leadSourceSubmissions.source, source),
        isNull(leadSourceSubmissions.contactedAt)
      ))
      .returning({ id: leadSourceSubmissions.id, contactedAt: leadSourceSubmissions.contactedAt })

    if (linha) return Response.json({ data: { id: linha.id, contacted_at: linha.contactedAt } })

    // Nada atualizado: ou já estava contatada, ou o id não é desta organização.
    const [existente] = await db
      .select({ id: leadSourceSubmissions.id, contactedAt: leadSourceSubmissions.contactedAt })
      .from(leadSourceSubmissions)
      .where(and(
        eq(leadSourceSubmissions.id, id),
        eq(leadSourceSubmissions.organizationId, auth.organizationId)
      ))
      .limit(1)

    if (!existente) return apiError(404, 'Lead não encontrado.')
    return Response.json({ data: { id: existente.id, contacted_at: existente.contactedAt } })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[submissions] POST falhou:', err)
    return apiError(500, 'Erro ao marcar o contato.')
  }
}
