/**
 * GET  /api/chavesnamao/chat/<chave> -- os leads de uma pessoa (cada um é uma mensagem), do mais antigo ao mais novo.
 * POST /api/chavesnamao/chat/<chave> -- abriu a conversa: os leads dela ficam lidos (crm_cnm_ler).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const CHAVE = /^[tel][^\s]{1,200}$/

export async function GET(req: NextRequest, { params }: { params: Promise<{ chave: string }> }) {
  try {
    await authenticateRequest(req)
    const { chave } = await params
    const c = decodeURIComponent(chave)
    if (!CHAVE.test(c)) return apiError(400, 'Conversa desconhecida.')
    const r = await naydb().query('SELECT crm_cnm_conversa($1) AS m', [c])
    return Response.json({ mensagens: r.rows[0]?.m ?? [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a conversa.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ chave: string }> }) {
  try {
    await authenticateRequest(req)
    const { chave } = await params
    const c = decodeURIComponent(chave)
    if (!CHAVE.test(c)) return apiError(400, 'Conversa desconhecida.')
    const r = await naydb().query('SELECT crm_cnm_ler($1) AS n', [c])
    return Response.json({ lidos: r.rows[0]?.n ?? 0 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui marcar a conversa como lida.')
  }
}
