/**
 * GET /api/imoveis-nay/dono?codigo=1778 -- o proprietário do imóvel pelo código (599), para a lupa da aba Proprietários da
 * v2 (Pedro, 04/11/2026: "pesquisar o código do imóvel 1778 ou #1778 e aparecer o número do proprietário").
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { donoDoImovel } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const codigo = Number(String(req.nextUrl.searchParams.get('codigo') || '').replace(/\D/g, ''))
    if (!Number.isInteger(codigo) || codigo <= 0) return apiError(400, 'Código inválido.')
    return Response.json({ dono: await donoDoImovel(codigo) })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o proprietário.')
  }
}
