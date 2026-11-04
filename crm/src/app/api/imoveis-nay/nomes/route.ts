/**
 * GET /api/imoveis-nay/nomes?codigos=840,3166 -- o nome de cada imóvel (o condomínio, ou tipo e bairro), para a faixa da aba
 * Proprietários da v2 (Pedro, 03/11/2026: "nem tem o nome dos condomínios deles"). A Parceria só sabe o código do imóvel do
 * dono; o nome vem do banco da Nay (crm_imoveis_nomes, 587).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { nomesDosImoveis } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const codigos = Array.from(new Set(String(req.nextUrl.searchParams.get('codigos') || '').split(',')
      .map((x) => Number(x.trim())).filter((n) => Number.isInteger(n) && n > 0))).slice(0, 500)
    return Response.json({ nomes: await nomesDosImoveis(codigos) })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os nomes dos imóveis.')
  }
}
