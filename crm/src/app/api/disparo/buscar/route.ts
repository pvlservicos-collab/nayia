/**
 * O disparo por faixa: acha os imóveis para a tela marcar (Tel, 28/09/2026):
 * "enviar intervalo de imóveis, aí eu posso selecionar uma faixa de renda,
 * bairro ou imobiliário e o sistema vai achar e marcar os imóveis para mim
 * confirmar visualmente e aí clico em enviar e ele envia".
 *
 * Só procura -- quem manda continua sendo o POST de `/api/disparo`, com as
 * mesmas paredes. A busca já devolve só o que a caixa de saída aceita (nosso,
 * disponível, no mercado): o que a tela marca é o que pode sair.
 *
 *   GET ?finalidade=aluguel|venda &vmin &vmax, e as listas repetindo o parâmetro:
 *       &bairro=A&bairro=B  &tipo=..  &mobilia=mobiliado|semi  &quartos=2&quartos=3 (4 = 4+)
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { buscarNaNay, TETO_POR_ENVIO, type FiltroFaixa } from '@/lib/nayDisparo'

/** "2.500" e "2500,00" viram 2500 -- o que vem depois da vírgula são centavos. */
function reais(v: string | null): number | null {
  const d = String(v || '').split(',')[0].replace(/\D/g, '')
  return d ? Number(d) : null
}

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const q = req.nextUrl.searchParams
    const fin = q.get('finalidade')
    const textos = (k: string, max: number) =>
      Array.from(new Set(q.getAll(k).map((v) => v.trim().slice(0, max)).filter(Boolean))).slice(0, 30)
    const f: FiltroFaixa = {
      finalidade: fin === 'aluguel' || fin === 'venda' ? fin : null,
      vmin: reais(q.get('vmin')),
      vmax: reais(q.get('vmax')),
      bairros: textos('bairro', 60),
      mobilias: textos('mobilia', 12).filter((m): m is 'mobiliado' | 'semi' => m === 'mobiliado' || m === 'semi'),
      tipos: textos('tipo', 40),
      quartos: Array.from(new Set(q.getAll('quartos').map(Number).filter((n) => Number.isInteger(n) && n >= 1 && n <= 9))),
    }
    if (!f.finalidade && f.vmin === null && f.vmax === null && !f.bairros.length && !f.mobilias.length
        && !f.tipos.length && !f.quartos.length) {
      return apiError(400, 'Escolha pelo menos um filtro: valor, bairro, mobília, tipo ou quartos.')
    }
    if (f.vmin !== null && f.vmax !== null && f.vmin > f.vmax) {
      return apiError(400, 'O valor mínimo está maior que o máximo.')
    }
    const itens = await buscarNaNay(f, 60, q.get('parceiros_novos') === '1')
    return Response.json({ itens, total: itens.length, teto: TETO_POR_ENVIO })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui procurar os imóveis.')
  }
}
