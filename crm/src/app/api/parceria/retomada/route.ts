/**
 * GET /api/parceria/retomada?telefone=55...  -- "onde ele parou".
 *
 * O resumo da conversa e o próximo passo, da revisão de 30/09 (migração 203,
 * sessão nay-ia-1b). É o que o card do lead mostra para quem abre uma conversa
 * velha e não sabe o que já foi dito.
 *
 * Um telefone por chamada, de propósito: quem pede é o card de UMA pessoa, e
 * uma lista inteira aqui viraria uma consulta grande a cada clique.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { retomadaDaParceria } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const telefone = String(req.nextUrl.searchParams.get('telefone') || '').trim()
    if (!telefone) return apiError(400, 'Sem telefone.')
    const mapa = await retomadaDaParceria([telefone])
    return Response.json({ retomada: mapa.get(telefone) ?? null })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler.')
  }
}
