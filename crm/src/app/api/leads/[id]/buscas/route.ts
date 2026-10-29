/**
 * GET /api/leads/{id}/buscas -- as buscas deste lead e os nossos imóveis que servem para cada uma (Pedro, 28/10/2026:
 * "deixar salvo essas buscas do lead como um cardzinho no contato deles no menu da direita do contato aberto").
 * Lê crm_lead_buscas(telefone) do banco da Nay (nayia 510): a análise grava privado.lead_busca, com a nota da Captação
 * ativa de cada imóvel; o "já enviado" é conferido na hora. 29/10: junto, a busca de agora (crm_lead_busca_ativa, 521).
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
    const [r, ativa] = await Promise.all([
      naydb().query('SELECT crm_lead_buscas($1) AS j', [lead.phone || '']),
      // 29/10 (nayia 521): a busca de agora -- situação, grupos, OLX, corretores e as etapas. Sem a 521, segue sem ela.
      naydb().query('SELECT crm_lead_busca_ativa($1) AS j', [lead.phone || '']).catch(() => ({ rows: [] as any[] })),
    ])
    return Response.json({ buscas: r.rows[0]?.j || [], ativa: ativa.rows[0]?.j || null })
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler as buscas')
  }
}
