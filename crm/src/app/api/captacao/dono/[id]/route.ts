/**
 * GET /api/captacao/dono/{leadId} -- o card do contato na conversa da captação
 * (Pedro, 29/09/2026, remontado em 01/10): quem é, os imóveis dele no catálogo
 * com quanto cada cadastro está preenchido, a ficha que a conversa abriu, as
 * fotos que ele mandou e o condomínio que ele citou na conversa (o "preencher
 * automático" do popup). É o que o "Atualizar", o "Editar dados" e o
 * "Cadastrar imóvel" levam (ver ./imovel/route.ts).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { imoveisDoDono, pontuacaoDosImoveis, condominioPeloTexto, donoDaCampanha } from '@/lib/nayLeitura'
import { donoDaConversa, fotosDaConversa, textoDaConversa } from '@/lib/donoDaCaptacao'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const { id } = await params
    const dono = await donoDaConversa(organizationId, id)
    if (!dono) return Response.json({ dono: null })
    const [{ imoveis, ficha }, fotos, texto, campanha] = await Promise.all([
      imoveisDoDono(dono.captacaoId), fotosDaConversa(id), textoDaConversa(id), donoDaCampanha(dono.captacaoId),
    ])
    /* a barra de cada imóvel (244) e o condomínio que ele citou (246) */
    const [pontuacao, condominiosCitados] = await Promise.all([
      pontuacaoDosImoveis(imoveis.map((i) => i.codigo)),
      condominioPeloTexto([texto, dono.condominio || ''].join(' ')),
    ])
    const { telefone: _t, lid: _l, ...semContato } = dono
    return Response.json({ dono: semContato, campanha, imoveis, ficha, fotos, pontuacao, condominiosCitados })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o proprietário.')
  }
}
