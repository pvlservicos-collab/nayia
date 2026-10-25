/**
 * GET /api/agentes?horas=24 -- o painel da aba Arquitetura da Nay Leads (Pedro, 24/10/2026: "uma opção ali do lado de
 * agenda, Arquitetura, lá vai ter cada etapa num fluxograma só para eu ver como está funcionando").
 * Uma chamada ao banco da Nay: crm_agentes_painel(horas) (nayia 489) -- por agente: ativações, conversas, tempo médio,
 * custo, tokens, erros; os caminhos que o mestre escolheu; o veto dos imóveis; o último replay.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const h = Number(req.nextUrl.searchParams.get('horas') || 24)
    const horas = Number.isFinite(h) ? Math.min(24 * 90, Math.max(1, Math.round(h))) : 24
    const r = await naydb().query('SELECT crm_agentes_painel($1) AS j', [horas])
    return Response.json(r.rows[0]?.j || {})
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler o painel dos agentes')
  }
}
