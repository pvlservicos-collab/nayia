import { NextRequest, NextResponse } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities, integrations } from '@/lib/schema'
import { eq, and, isNull, ilike, or, desc, sql, inArray } from 'drizzle-orm'
import type { LeadWithOwner, SearchHit } from '@/lib/types'
import { mapLead } from '@/lib/mappers'
import { linhaDoTipo, LINHA_DO_TIPO } from '@/lib/leadChannel'

export const dynamic = 'force-dynamic'

/* sem acento e minúsculo, dos dois lados (o crmdb não tem a extensão unaccent) */
const COM_ACENTO = 'áàâãäéèêëíìîïóòôõöúùûüçñ'
const SEM_ACENTO = 'aaaaaeeeeiiiiooooouuuucn'
const semAcento = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({} as any))
    const q = (body.q ?? '').trim()
    const limit = Math.min(Math.max(body.limit ?? 100, 1), 100)

    if (q.length < 2) {
      return NextResponse.json({ error: 'q must be at least 2 characters' }, { status: 400 })
    }

    const auth = await authenticateRequest(req)
    const searchTerm = `%${q}%`

    /* BUSCA DE VERDADE EM TODO O NÚMERO (Pedro, 30/09/2026: "a lupa de buscar
       contato nas conversas quero que funcione como uma busca real de leads em
       todo o número; hoje se eu tô no Tel só acho quem é do Tel").
       - `linha`: a busca é só do número da aba (antes pegava 50 da organização
         inteira e a lista jogava fora os de outro número -- com nome comum, os
         da Parceria nem chegavam);
       - sem acento dos dois lados ("joao" acha "João");
       - número em qualquer formato ("92 98144-5964", "981445964"): compara os
         dígitos, e com 8 ou mais só os 8 últimos (com e sem o 9). */
    const linha = typeof body.linha === 'string' ? body.linha : null
    const tiposDaLinha = linha ? Object.entries(LINHA_DO_TIPO).filter(([, l]) => l === linha).map(([t]) => t) : []
    const naLinha = linha && tiposDaLinha.length
      ? (linha === 'parceria'
          ? or(inArray(integrations.type, tiposDaLinha), and(sql`${leads.integrationId} IS NOT NULL`, isNull(integrations.type)))!
          : inArray(integrations.type, tiposDaLinha))
      : sql`true`
    const qSem = `%${semAcento(q)}%`
    const digitos = q.replace(/\D/g, '')
    const pedacoDoNumero = digitos.length >= 8 ? digitos.slice(-8) : digitos
    const porNumero = pedacoDoNumero.length >= 4
      ? sql`regexp_replace(coalesce(${leads.phone}, ''), '[^0-9]', '', 'g') LIKE ${'%' + pedacoDoNumero + '%'}`
      : sql`false`

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
        naLinha,
        or(
          sql`translate(lower(coalesce(${leads.title}, '')), ${COM_ACENTO}, ${SEM_ACENTO}) LIKE ${qSem}`,
          ilike(leads.phone, searchTerm), ilike(leads.email, searchTerm), porNumero,
        )
      ))
      .orderBy(desc(leads.lastActivityAt))
      .limit(limit)
    const leadResults = linhasEncontradas.map((r) => r.lead)
    const tipoPorLead = new Map(linhasEncontradas.map((r) => [r.lead.id, r.integrationType]))

    // mensagens: também só do número da aba
    const activityResults = await db.select({ leadId: leadActivities.leadId, content: leadActivities.content, createdAt: leadActivities.createdAt })
      .from(leadActivities)
      .innerJoin(leads, eq(leads.id, leadActivities.leadId))
      .leftJoin(integrations, eq(integrations.id, leads.integrationId))
      .where(and(eq(leadActivities.organizationId, auth.organizationId), isNull(leads.deletedAt), naLinha,
                 ilike(leadActivities.content, searchTerm)))
      .orderBy(desc(leadActivities.createdAt))
      .limit(limit)

    const leadMap = new Map(leadResults.map(l => [l.id, l]))
    /* quem só bateu pela MENSAGEM também entra: antes a conversa achada pelo que
       foi escrito só aparecia se o nome também batesse */
    const faltam = [...new Set(activityResults.map((a) => a.leadId))].filter((id) => !leadMap.has(id))
    if (faltam.length) {
      const extras = await db.select({ lead: leads, integrationType: integrations.type })
        .from(leads)
        .leftJoin(integrations, eq(integrations.id, leads.integrationId))
        .where(and(eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt), inArray(leads.id, faltam)))
      for (const r of extras) { leadMap.set(r.lead.id, r.lead); tipoPorLead.set(r.lead.id, r.integrationType) }
    }

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
