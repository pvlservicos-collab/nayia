/**
 * GET /api/captacao/dono/{leadId}/imovel/{codigo} -- os campos de hoje de um
 * imóvel, para o popup do card abrir já preenchido (Pedro, 01/10/2026: "uma
 * opção de alterar os dados do imóvel dele lá pelo card").
 *
 * Só abre o que é DELE ou um pré-cadastro (Rascunho, que é onde a OLX deixa o
 * que foi capturado e qualquer um pode puxar). Imóvel de outra pessoa, no ar,
 * não é assunto deste card.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { imoveisDoDono, imovelParaCadastro } from '@/lib/nayLeitura'
import { donoDaConversa } from '@/lib/donoDaCaptacao'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string; codigo: string }> }) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const { id, codigo: cru } = await params
    if (!/^\d{1,6}$/.test(cru)) return apiError(400, 'código inválido')
    const codigo = Number(cru)

    const dono = await donoDaConversa(organizationId, id)
    if (!dono) return apiError(404, 'Esta conversa não é de um proprietário da captação.')
    const imovel = await imovelParaCadastro(codigo)
    if (!imovel) return apiError(404, `O imóvel ${codigo} não está no catálogo.`)

    const { imoveis } = await imoveisDoDono(dono.captacaoId)
    const dele = imoveis.some((i) => i.codigo === codigo)
    if (!dele && String(imovel.status || '') !== 'Rascunho') {
      return apiError(403, `O imóvel ${codigo} não é deste proprietário.`)
    }
    return Response.json({ imovel, dele })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o imóvel.')
  }
}
