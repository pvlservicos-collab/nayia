/**
 * POST /api/captacao/dono/{leadId}/imovel -- os botões do card do
 * proprietário (Pedro, 29/09/2026):
 *   { codigo }       "Atualizar": o imóvel dele recebe o que a ficha tem (só
 *                    campos vazios, a situação não muda) e as fotos marcadas;
 *   { codigo: null } "Cadastrar imóvel": pré-cadastro novo (Rascunho), ligado
 *                    ao dono, com a ficha de imóvel novo e as fotos marcadas.
 *   { dados }        o que a pessoa preencheu no popup (01/10/2026): entra por
 *                    CIMA do que estava, porque ela preencheu olhando os
 *                    valores de hoje. A situação continua fora: quem põe no ar
 *                    é o humano, no editor.
 * `fotos` são ids das mensagens de foto desta conversa. Devolve o código, o
 * quanto o cadastro ficou preenchido (244) e o endereço do editor do site.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { lerMidia } from '@/lib/armazem'
import { donoDaConversa, fotosDaConversa } from '@/lib/donoDaCaptacao'
import { cadastrarNoSite, mandarFotoAoSite } from '@/lib/siteCaptacao'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 300

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    const codigo = /^\d{1,6}$/.test(String(corpo?.codigo ?? '')) ? Number(corpo.codigo) : null
    const pedidas = Array.isArray(corpo?.fotos) ? new Set((corpo.fotos as unknown[]).map(String)) : new Set<string>()

    const dono = await donoDaConversa(organizationId, id)
    if (!dono) return apiError(404, 'Esta conversa não é de um proprietário da captação.')

    const feito = await cadastrarNoSite(dono.captacaoId, codigo, corpo?.dados)

    // as fotos marcadas, só desta conversa, na ordem em que ele mandou
    const daConversa = (await fotosDaConversa(id, 200)).filter((f) => pedidas.has(f.id)).reverse()
    let ok = 0
    const falharam: string[] = []
    for (const f of daConversa) {
      try {
        const midia = await lerMidia(f.url)
        if (!midia?.dados?.length) throw new Error('arquivo não encontrado')
        await mandarFotoAoSite(feito.codigo, midia.dados, f.id.replace(/-/g, ''))
        ok++
      } catch (e: any) {
        falharam.push(f.id)
        console.error('[captação → site] foto', f.id, e?.message || e)
      }
    }
    return Response.json({ ...feito, fotos: ok, fotosFalharam: falharam.length })
  } catch (err: any) {
    console.error('[captação → site]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui cadastrar no site.')
  }
}
