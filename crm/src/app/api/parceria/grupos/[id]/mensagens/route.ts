/**
 * GET  /api/parceria/grupos/<id>/mensagens[?antes=<iso>] -> { mensagens } (as guardadas, da mais nova à mais velha)
 * POST /api/parceria/grupos/<id>/mensagens { texto } -> manda pelo número da Parceria
 * A Z-API não entrega o histórico: o que aparece é o que foi guardado do webhook (migração 277).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { mandarNoGrupo, mensagensDoGrupo } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    await authenticateRequest(req)
    const { id } = await params
    return Response.json({ mensagens: await mensagensDoGrupo(decodeURIComponent(id), req.nextUrl.searchParams.get('antes')) })
  } catch (err: any) {
    console.error('[grupos] mensagens', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as mensagens.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    const texto = String(corpo?.texto || '').trim()
    if (!texto) return apiError(400, 'Escreva a mensagem.')
    if (texto.length > 4000) return apiError(400, 'Mensagem longa demais (até 4.000 letras).')
    const messageId = await mandarNoGrupo(auth.organizationId, decodeURIComponent(id), texto)
    console.log('[grupos] mensagem em %s por %s', String(id).slice(-10), auth.memberId || 'api')
    return Response.json({ ok: true, messageId })
  } catch (err: any) {
    console.error('[grupos] mandar', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar a mensagem.')
  }
}
