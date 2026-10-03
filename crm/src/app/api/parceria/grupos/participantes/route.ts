/**
 * GET /api/parceria/grupos/participantes -> planilha (CSV) de TODOS os grupos: uma linha por pessoa, com
 * em quantos e em quais grupos ela está, o nome que a casa conhece e se é corretor cadastrado.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { csvDeTodos } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const hoje = new Date().toISOString().slice(0, 10)
    return new Response(await csvDeTodos(auth.organizationId), {
      headers: { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': `attachment; filename="grupos-participantes-${hoje}.csv"` },
    })
  } catch (err: any) {
    console.error('[grupos] planilha de todos', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a planilha.')
  }
}
