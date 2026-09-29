import { NextRequest, NextResponse } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities, integrations } from '@/lib/schema'
import { eq, and, isNull, ilike, or, desc, sql } from 'drizzle-orm'
import type { LeadWithOwner, SearchHit } from '@/lib/types'
import { mapLead } from '@/lib/mappers'
import { linhaDoTipo } from '@/lib/leadChannel'

export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({} as any))
    const q = (body.q ?? '').trim()
    const limit = Math.min(Math.max(body.limit ?? 50, 1), 100)

    if (q.length < 2) {
      return NextResponse.json({ error: 'q must be at least 2 characters' }, { status: 400 })
    }

    const auth = await authenticateRequest(req)
    const searchTerm = `%${q}%`

    /* O TIPO DA INTEGRACAO VEM NO JOIN. Sem ele o resultado da busca chegava com
       `integration: undefined`, e a aba da API Oficial ficava vazia ao pesquisar
       -- o `getLinhaWhatsapp` sem tipo cai sempre na parceria. */
    const linhasEncontradas = await db
      .select({ lead: leads, integrationType: integrations.type })
      .from(leads)
      .leftJoin(integrations, eq(integrations.id, leads.integrationId))
      .where(and(
        eq(leads.organizationId, auth.organizationId),
        isNull(leads.deletedAt),
        or(ilike(leads.title, searchTerm), ilike(leads.phone, searchTerm), ilike(leads.email, searchTerm))
      ))
      .limit(limit)
    const leadResults = linhasEncontradas.map((r) => r.lead)
    const tipoPorLead = new Map(linhasEncontradas.map((r) => [r.lead.id, r.integrationType]))

    const activityResults = await db.select({ leadId: leadActivities.leadId, content: leadActivities.content, createdAt: leadActivities.createdAt })
      .from(leadActivities)
      .where(and(eq(leadActivities.organizationId, auth.organizationId), ilike(leadActivities.content, searchTerm)))
      .orderBy(desc(leadActivities.createdAt))
      .limit(limit)

    const leadMap = new Map(leadResults.map(l => [l.id, l]))

    /* A LINHA DE CADA CONVERSA -- a mesma regra da lista (`linhasDe` em
       /api/leads): a do lead, e só ela. Cada lead é de uma linha desde 28/09
       (ver `leadDaLinha.ts`), então procurar na aba da captação não traz a
       conversa da Parceria. */
    function comLinhas(lead: typeof leadResults[number]): LeadWithOwner {
      const tipo = tipoPorLead.get(lead.id) ?? null
      const doLead = linhaDoTipo(tipo) ?? (lead.integrationId && !tipo ? 'parceria' : null)
      return {
        ...(mapLead(lead) as unknown as LeadWithOwner),
        integration: tipo ? ({ type: tipo } as any) : undefined,
        linhas: doLead ? [doLead] : [],
      }
    }

    const hits: SearchHit[] = [
      ...leadResults.map(lead => ({
        lead: comLinhas(lead),
        matchType: 'title' as const,
        snippet: undefined,
        matchedAt: lead.lastActivityAt?.toString(),
      })),
    ]

    const seenLeadIds = new Set(leadResults.map(l => l.id))
    for (const act of activityResults) {
      if (!seenLeadIds.has(act.leadId)) {
        seenLeadIds.add(act.leadId)
        const lead = leadMap.get(act.leadId)
        if (lead) {
          hits.push({
            lead: comLinhas(lead),
            matchType: 'message' as const,
            snippet: act.content?.slice(0, 120) || undefined,
            matchedAt: act.createdAt?.toString(),
          })
        }
      }
    }

    return NextResponse.json({ hits })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
