/**
 * GET /api/parceria/painel -- os números da Nay para o painel de métricas da
 * Parceria (ver src/components/Chat/BarraDeMetricas.tsx e a migração 175).
 * Guarda 20 s: a barra pede a cada 30 s em cada tela aberta.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { painelDaNay, nayLigada, type PainelDaNay, type EstadoDaNay } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

let guardado: { em: number; painel: PainelDaNay; nay: EstadoDaNay } | null = null

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    if (!guardado || Date.now() - guardado.em > 20_000) {
      const [painel, nay] = await Promise.all([painelDaNay(), nayLigada()])
      guardado = { em: Date.now(), painel, nay }
    }
    return Response.json(guardado)
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os números da Nay.')
  }
}
