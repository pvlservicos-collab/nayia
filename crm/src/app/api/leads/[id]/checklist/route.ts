/**
 * POST /api/leads/{id}/checklist { tipo: 'locacao' | 'venda' } -- o botão
 * "Enviar checklist" do card do corretor (Pedro, 29/09/2026: "abre uma opção
 * de checklist venda ou aluguel, e enviar, a Nay envia"). Vai pela caixa da
 * Nay, como o comando "checklist aluguel para 92 ..." (migrações 183 e 184).
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, organizationMembers, profiles } from '@/lib/schema'
import { checklistPelaNay } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    const tipo = corpo?.tipo === 'venda' ? 'venda' : corpo?.tipo === 'locacao' ? 'locacao' : null
    if (!tipo) return apiError(400, 'Escolha: aluguel ou venda.')

    const [lead] = await db
      .select({ phone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    if (!lead.phone || lead.phone.replace(/\D/g, '').length < 10) return apiError(400, 'Esta conversa não tem o número do corretor.')

    let quem = 'CRM'
    if (auth.memberId) {
      const [m] = await db.select({ nome: profiles.fullName }).from(organizationMembers)
        .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
        .where(eq(organizationMembers.id, auth.memberId)).limit(1)
      quem = `CRM: ${m?.nome || 'equipe'}`
    }
    const resumo = await checklistPelaNay(lead.phone, tipo, quem)
    const ok = resumo.startsWith('Mandei')
    return ok ? Response.json({ ok, resumo }) : apiError(400, resumo || 'A Nay não mandou.')
  } catch (err: any) {
    console.error('[checklist]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui pedir o checklist à Nay.')
  }
}
