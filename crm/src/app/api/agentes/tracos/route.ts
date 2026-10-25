/**
 * GET /api/agentes/tracos?limite=40&antes=<id>&telefone=... -- o registro de fluxos da aba Arquitetura (Pedro, 25/10/2026:
 * "deixe lá onde tem o fluxo um registro de fluxos, onde a nay passou e quais ferramentas passou, tipo um log de traços").
 * Uma chamada ao banco da Nay: crm_agentes_tracos(limite, antes, telefone) (nayia 490) -- os turnos mais recentes, cada um
 * com os passos em ordem (o agente, a ferramenta, o resumo, ms, tokens, custo, erro e o detalhe). `antes` pagina: o
 * `primeiro` do último turno da página.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const q = req.nextUrl.searchParams
    const l = Number(q.get('limite') || 40)
    const limite = Number.isFinite(l) ? Math.min(200, Math.max(1, Math.round(l))) : 40
    const a = Number(q.get('antes'))
    const antes = Number.isFinite(a) && a > 0 ? Math.round(a) : null
    const telefone = (q.get('telefone') || '').replace(/\D/g, '') || null
    const r = await naydb().query('SELECT crm_agentes_tracos($1, $2, $3) AS j', [limite, antes, telefone])
    return Response.json(r.rows[0]?.j || { turnos: [] })
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler o registro de fluxos')
  }
}
