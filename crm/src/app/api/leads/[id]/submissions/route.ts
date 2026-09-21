/**
 * GET /api/leads/{id}/submissions — o que as fontes externas mandaram sobre
 * este lead.
 *
 * Existe pro painel do lead (chat e Pipeline) conseguir mostrar a agenda montada
 * e as respostas do quiz da Agenda em Ascensão. Esses dados vivem em
 * `lead_source_submissions.payload`, não em `leads`: a tabela de leads guarda o
 * que todo lead tem, e o quiz é de uma fonte só.
 *
 * Casa por `lead_id` e, também, pelo telefone. O telefone entra porque nem toda
 * linha ficou ligada ao lead: se a criação do lead falhou na ingestão, ou se o
 * lead já existia com outro histórico, a linha continua lá com o número certo e
 * sem `lead_id`. Sem esse segundo caminho, o painel do lead ficaria vazio
 * justamente nos casos que alguém foi conferir.
 */
import { NextRequest } from 'next/server'
import { and, desc, eq, or } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadSourceSubmissions, leads } from '@/lib/schema'
import { LEAD_SOURCES, isLeadSourceKey } from '@/lib/leadSources'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [lead] = await db
      .select({ id: leads.id, phone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId)))
      .limit(1)

    if (!lead) return apiError(404, 'Lead não encontrado.')

    const casaLead = eq(leadSourceSubmissions.leadId, lead.id)
    const casa = lead.phone
      ? or(casaLead, eq(leadSourceSubmissions.phone, lead.phone))
      : casaLead

    const rows = await db
      .select({
        id: leadSourceSubmissions.id,
        source: leadSourceSubmissions.source,
        externalId: leadSourceSubmissions.externalId,
        name: leadSourceSubmissions.name,
        email: leadSourceSubmissions.email,
        phone: leadSourceSubmissions.phone,
        instagram: leadSourceSubmissions.instagram,
        payload: leadSourceSubmissions.payload,
        receivedAt: leadSourceSubmissions.receivedAt,
        updatedAt: leadSourceSubmissions.updatedAt,
      })
      .from(leadSourceSubmissions)
      .where(and(eq(leadSourceSubmissions.organizationId, auth.organizationId), casa))
      // Mais recente primeiro: quando o mesmo lead aparece em mais de uma fonte
      // (entrou pela lista antiga e voltou pelo site), o painel abre no último.
      .orderBy(desc(leadSourceSubmissions.updatedAt))

    const data = rows.map((row) => ({
      id: row.id,
      source: row.source,
      source_label: isLeadSourceKey(row.source) ? LEAD_SOURCES[row.source].label : row.source,
      external_id: row.externalId,
      name: row.name,
      email: row.email,
      phone: row.phone,
      instagram: row.instagram,
      payload: (row.payload ?? {}) as Record<string, any>,
      received_at: row.receivedAt,
      updated_at: row.updatedAt,
    }))

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro interno.')
  }
}

