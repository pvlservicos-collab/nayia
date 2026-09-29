/**
 * GET /api/parceria/visitas/{id} -- o andamento de uma visita, passo a passo
 * (o registro que a Nay grava a cada mudança: pedida, corretor confirmou,
 * aprovada, proprietário OK, André OK, confirmada, realizada...).
 *
 * POST /api/parceria/visitas/{id} -- mexer na visita pela agenda (29/09/2026):
 *   { acao: 'horario', quando: ISO }  muda a hora; ninguém é avisado
 *   { acao: 'realizada' }             a Nay pergunta ao corretor como foi
 *   { acao: 'excluir' }               some da agenda; ninguém é avisado
 *   { acao: 'editar', campo, valor }  o lápis: imóvel, visitante, proprietário, acesso
 * O nome de quem fez vai para o andamento da visita.
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { CAMPOS_EDITAVEIS_DA_VISITA, editarVisita, eventosDaVisita, mexerNaVisita, type AcaoNaVisita, type CampoDaVisita } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function idDaVisita(bruto: string): number | null {
  const n = Number(bruto)
  return Number.isInteger(n) && n > 0 ? n : null
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    await authenticateRequest(req)
    const n = idDaVisita((await params).id)
    if (!n) return apiError(400, 'Visita inválida.')
    return Response.json({ eventos: await eventosDaVisita(n) })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o andamento da visita.')
  }
}

const ACOES: AcaoNaVisita[] = ['horario', 'realizada', 'excluir']

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    // só gente logada: o token de API (n8n, integrações) não mexe em visita
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM pode mexer na visita.')
    const n = idDaVisita((await params).id)
    if (!n) return apiError(400, 'Visita inválida.')

    const corpo = await req.json().catch(() => null)
    const [perfilDeQuem] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    if (corpo?.acao === 'editar') {
      const campo = corpo?.campo as CampoDaVisita
      if (!CAMPOS_EDITAVEIS_DA_VISITA.includes(campo)) return apiError(400, 'Campo inválido.')
      const valor = corpo?.valor == null ? null : String(corpo.valor).slice(0, 200)
      const r = await editarVisita(n, campo, valor, perfilDeQuem?.nome?.trim() || 'alguém no CRM')
      return Response.json(r, { status: r.ok ? 200 : 409 })
    }
    const acao = corpo?.acao as AcaoNaVisita
    if (!ACOES.includes(acao)) return apiError(400, 'Ação inválida.')
    let quando: Date | undefined
    if (acao === 'horario') {
      quando = new Date(String(corpo?.quando || ''))
      if (isNaN(quando.getTime())) return apiError(400, 'Horário inválido.')
    }

    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const quem = perfil?.nome?.trim() || 'alguém no CRM'

    const r = await mexerNaVisita(n, acao, quem, quando)
    return Response.json(r, { status: r.ok ? 200 : 409 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui mexer na visita.')
  }
}
