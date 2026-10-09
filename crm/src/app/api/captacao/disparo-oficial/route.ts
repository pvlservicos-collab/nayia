/**
 * GET /api/captacao/disparo-oficial -- a barrinha do disparo pela API oficial (ver
 * src/components/Chat/BarraDoDisparoOficial.tsx e a migração 331). Guarda 20 s: a barra pede a cada 30 s.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { disparoOficial, type DisparoOficial } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

let guardado: { em: number; disparo: DisparoOficial | null } | null = null

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    if (!guardado || Date.now() - guardado.em > 20_000) guardado = { em: Date.now(), disparo: await disparoOficial() }
    return Response.json({ disparo: guardado.disparo })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o disparo da API oficial.')
  }
}
