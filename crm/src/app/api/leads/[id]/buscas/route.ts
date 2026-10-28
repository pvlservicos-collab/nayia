/**
 * GET /api/leads/{id}/buscas -- as buscas deste lead e os nossos imóveis que servem para cada uma (Pedro, 28/10/2026:
 * "deixar salvo essas buscas do lead como um cardzinho no contato deles no menu da direita do contato aberto").
 * Lê crm_lead_buscas(telefone) do banco da Nay (nayia 510): a análise grava privado.lead_busca, com a nota da Captação
 * ativa de cada imóvel; o "já enviado" é conferido na hora.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ id: leads.id, phone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    const r = await naydb().query('SELECT crm_lead_buscas($1) AS j', [lead.phone || ''])
    return Response.json({ buscas: r.rows[0]?.j || [] })
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler as buscas')
  }
}
