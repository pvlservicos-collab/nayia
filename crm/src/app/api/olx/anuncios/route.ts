/**
 * GET /api/olx/anuncios?conta=proprietarios|corretores -- a aba Anúncios e a aba Informações do Chat OLX
 * (Pedro, 13/10/2026: "lá vai ter o chat, e os anúncios e todas as informações, em uma tab lá em cima como se
 * fosse um menu próprio dentro daquela aba").
 *
 * Devolve os anúncios da conta (o que a OLX lista + o que conhecemos pelas conversas), o estado da conta e o que
 * o nosso aplicativo usa (endereço de retorno e escopos). Só para quem está logado no CRM; nenhum segredo sai daqui.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { anunciosDaContaOlx, ehContaOlx, estadoDaContaOlx, informacoesDoAplicativoOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const conta = req.nextUrl.searchParams.get('conta')
    if (!ehContaOlx(conta)) return apiError(400, 'Diga a conta: proprietarios ou corretores.')
    const [estado, lista] = await Promise.all([estadoDaContaOlx(conta), anunciosDaContaOlx(conta)])
    return Response.json({ estado, ...lista, aplicativo: informacoesDoAplicativoOlx(), em: Date.now() })
  } catch (err: any) {
    console.error('[olx/anuncios]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os anúncios da OLX.')
  }
}
