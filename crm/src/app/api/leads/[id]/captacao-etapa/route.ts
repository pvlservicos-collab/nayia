/**
 * POST /api/leads/{id}/captacao-etapa -- a etapa da captação escolhida no card
 * (Pedro, 01/10/2026): "adicione lá na aba captação a mesma ferramenta de mudar
 * a etapa do lead que nem na parceria, mas com as etapas da captação, e adicione
 * mais uma etapa: follow-up".
 *
 * Quem decide é a migração 242 (`crm_captacao_etapa_manual`): a escolha à mão
 * SUBSTITUI a etapa que a campanha deduziu, "Todos" solta e devolve à campanha,
 * e "Com o Tel" cala a Nay para essa pessoa até voltar para Todos.
 * A fila de disparo não é tocada.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, profiles } from '@/lib/schema'
import { escolherEtapaDaCaptacao } from '@/lib/nayLeitura'
import { invalidarDonosDaCaptacao } from '@/app/api/captacao/donos/route'

export const ETAPAS_DA_CAPTACAO = ['todos', 'em_andamento', 'followup', 'disponiveis', 'alugados',
  'quer_vender', 'ja_vendeu', 'tem_outro_imovel', 'sem_resposta', 'com_o_tel', 'rayssa', 'lucas'] as const

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM muda a etapa.')
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    const etapa = String(corpo?.etapa || '')
    if (!(ETAPAS_DA_CAPTACAO as readonly string[]).includes(etapa)) return apiError(400, 'Etapa desconhecida.')

    const [lead] = await db
      .select({ telefone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    if (!lead.telefone) return apiError(409, 'Esta conversa não tem telefone: a etapa da captação é por número.')

    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const r = await escolherEtapaDaCaptacao(lead.telefone, etapa, perfil?.nome?.trim() || 'alguém no CRM')
    if (r.ok) invalidarDonosDaCaptacao(auth.organizationId)
    return Response.json({ ...r, etapa }, { status: r.ok ? 200 : 409 })
  } catch (err: any) {
    console.error('[captacao-etapa]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mudar a etapa.')
  }
}
