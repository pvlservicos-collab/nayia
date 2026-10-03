/**
 * GET  /api/parceria/grupos/<id>[?fresco=1] -> os dados do grupo (participantes com nome, configurações)
 * POST /api/parceria/grupos/<id> { acao, ... } -> edita (nome, descricao, config, adicionar, remover,
 *      promover, rebaixar) e devolve { grupo, conferido }: o grupo RELIDO depois da mudança.
 * Só funciona onde o número da Parceria é admin. Ver src/lib/gruposParceria.ts.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { dadosDoGrupo, editarGrupo, type AcaoNoGrupo } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const ACOES = new Set(['nome', 'descricao', 'config', 'adicionar', 'remover', 'promover', 'rebaixar'])

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    return Response.json(await dadosDoGrupo(auth.organizationId, decodeURIComponent(id), req.nextUrl.searchParams.get('fresco') === '1'))
  } catch (err: any) {
    console.error('[grupos] dados', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o grupo.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    if (!ACOES.has(String(corpo?.acao))) return apiError(400, 'Ação desconhecida.')
    if (corpo.acao === 'nome' && !String(corpo.nome || '').trim()) return apiError(400, 'O nome não pode ficar vazio.')
    if (['adicionar', 'remover', 'promover', 'rebaixar'].includes(corpo.acao) && !Array.isArray(corpo.telefones)) {
      return apiError(400, 'Diga os telefones.')
    }
    const r = await editarGrupo(auth.organizationId, decodeURIComponent(id), corpo as AcaoNoGrupo)
    console.log('[grupos] %s em %s por %s: %s', corpo.acao, String(id).slice(-10), auth.memberId || 'api', r.conferido ? 'conferido' : 'NÃO apareceu no grupo')
    return Response.json(r)
  } catch (err: any) {
    console.error('[grupos] editar', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mudar o grupo.')
  }
}
