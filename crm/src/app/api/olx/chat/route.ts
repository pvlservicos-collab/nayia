/**
 * GET /api/olx/chat?conta=proprietarios|corretores -- a aba de UMA conta da OLX no CRM (Pedro, 08/10/2026):
 * o estado da conta (conectada? webhook ligado?) e as conversas, a mais recente primeiro.
 * Só para quem está logado no CRM. Ver src/lib/olxChat.ts.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { chatsDaContaOlx, ehContaOlx, estadoDaContaOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const conta = req.nextUrl.searchParams.get('conta')
    if (!ehContaOlx(conta)) return apiError(400, 'Diga a conta: proprietarios ou corretores.')
    const [estado, chats] = await Promise.all([estadoDaContaOlx(conta), chatsDaContaOlx(conta)])
    return Response.json({ estado, chats, em: Date.now() })
  } catch (err: any) {
    console.error('[olx/chat]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as conversas da OLX.')
  }
}
