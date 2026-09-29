/**
 * GET /api/captacao/placar -- os números da barra da captação (ver
 * src/components/Chat/BarraDaCaptacao.tsx e a migração 178). Guarda 20 s: a
 * barra pede a cada 30 s em cada tela aberta.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { placarDaCaptacao, type PlacarDaCaptacao } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

let guardado: { em: number; placar: PlacarDaCaptacao } | null = null

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    if (!guardado || Date.now() - guardado.em > 20_000) guardado = { em: Date.now(), placar: await placarDaCaptacao() }
    return Response.json({ placar: guardado.placar })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os números da captação.')
  }
}
