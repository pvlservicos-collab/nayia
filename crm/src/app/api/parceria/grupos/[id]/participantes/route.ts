/**
 * GET /api/parceria/grupos/<id>/participantes -> planilha (CSV) com os participantes do grupo:
 * telefone, nome que a casa conhece, admin, corretor cadastrado, já falou com a Nay.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { csvDoGrupo, dadosDoGrupo } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const g = await dadosDoGrupo(auth.organizationId, decodeURIComponent(id))
    const arquivo = 'grupo-' + g.nome.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^\w]+/g, '-').replace(/^-|-$/g, '').toLowerCase().slice(0, 50)
    return new Response(csvDoGrupo(g), {
      headers: { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': `attachment; filename="${arquivo || 'grupo'}.csv"` },
    })
  } catch (err: any) {
    console.error('[grupos] planilha', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a planilha.')
  }
}
