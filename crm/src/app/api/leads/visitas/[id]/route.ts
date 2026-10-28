/**
 * POST /api/leads/visitas/{id} -- VISITA REALIZADA numa visita da Nay Leads (número 8595), pela agenda
 * (Pedro, 28/10/2026): "eles vão acontecer quando a Rayssa marcar lá na aba visita, clicar na visita e clicar em
 * VISITA REALIZADA, aí ela vai perguntar, ou para o cliente ou para o corretor".
 *   { acao: 'realizada', para: 'cliente' | 'corretor' }
 * O id é o da privado.olx_visita (na agenda ele aparece negativo). A regra mora no banco
 * (crm_visita_leads_realizada, 513); a pergunta sai pelo nay-olx, uma vez só. O nome de quem marcou fica na visita.
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { visitaDosLeadsRealizada } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    // só gente logada: o token de API (n8n, integrações) não mexe em visita
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM pode mexer na visita.')
    const n = Number((await params).id)
    if (!Number.isInteger(n) || n <= 0) return apiError(400, 'Visita inválida.')
    const corpo = await req.json().catch(() => null)
    if (corpo?.acao !== 'realizada') return apiError(400, 'Ação inválida.')
    const para = corpo?.para === 'corretor' ? 'corretor' : corpo?.para === 'cliente' ? 'cliente' : null
    if (!para) return apiError(400, 'Escolha se a Nay pergunta ao cliente ou ao corretor.')

    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const r = await visitaDosLeadsRealizada(n, para, perfil?.nome?.trim() || 'alguém no CRM')
    return Response.json(r, { status: r.ok ? 200 : 409 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui marcar a visita.')
  }
}
