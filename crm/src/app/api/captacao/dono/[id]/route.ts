/**
 * GET /api/captacao/dono/{leadId} -- o card do proprietário na conversa da
 * captação (Pedro, 29/09/2026): quem é, os imóveis dele no catálogo, a ficha
 * que a conversa abriu e as fotos que ele mandou. É o que o "Atualizar" e o
 * "Cadastrar imóvel" levam (ver ./imovel/route.ts).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { imoveisDoDono } from '@/lib/nayLeitura'
import { donoDaConversa, fotosDaConversa } from '@/lib/donoDaCaptacao'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const { id } = await params
    const dono = await donoDaConversa(organizationId, id)
    if (!dono) return Response.json({ dono: null })
    const [{ imoveis, ficha }, fotos] = await Promise.all([imoveisDoDono(dono.captacaoId), fotosDaConversa(id)])
    const { telefone: _t, lid: _l, ...semContato } = dono
    return Response.json({ dono: semContato, imoveis, ficha, fotos })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o proprietário.')
  }
}
