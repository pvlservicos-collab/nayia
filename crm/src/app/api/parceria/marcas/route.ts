/**
 * GET /api/parceria/marcas -- o que a Nay sabe de cada conversa da Parceria
 * (29/09/2026): é proprietário (e de quais imóveis), é corretor, tem visita
 * aberta, o Tel está com a conversa. É o que alimenta os filtros de cima
 * (Proprietários, Visitas, Tel) e as marcas de cada linha da lista.
 *
 * Devolve { marcas: { <leadId>: MarcaDaNay }, nay: { ligada, motivo } } -- o
 * segundo é a chave geral da Nay, para o robô do cabeçalho (29/09). A consulta à Nay leva ~1 s
 * para as ~130 conversas; por isso guarda 45 s, e dois pedidos ao mesmo
 * tempo esperam a mesma consulta em vez de fazer duas. `?fresco=1` ignora a
 * cópia guardada.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { marcasDaNay, nayLigada, type EstadoDaNay, type MarcaDaNay } from '@/lib/nayLeitura'
import { conversasDaParceria } from '@/lib/conversasDaParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const VALIDADE_MS = 45_000
type Marcas = Record<string, MarcaDaNay>
type Resposta = { marcas: Marcas; nay: EstadoDaNay }
const guardadas = new Map<string, { em: number } & Resposta>()
const emAndamento = new Map<string, Promise<Resposta>>()

async function calcular(organizacao: string): Promise<Resposta> {
  const conversas = await conversasDaParceria(organizacao)
  const [porTelefone, nay] = await Promise.all([
    marcasDaNay(conversas.map((c) => c.telefone || '').filter(Boolean)),
    nayLigada().catch((e) => ({ ligada: false, motivo: `Não consegui ler a Nay: ${e?.message || e}` })),
  ])
  const marcas: Marcas = {}
  for (const c of conversas) {
    const m = c.telefone ? porTelefone.get(c.telefone) : undefined
    if (m) marcas[c.id] = m
  }
  return { marcas, nay }
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId
    const guardada = guardadas.get(org)
    const fresco = req.nextUrl.searchParams.get('fresco') === '1'
    if (guardada && !fresco && Date.now() - guardada.em < VALIDADE_MS) {
      return Response.json({ marcas: guardada.marcas, nay: guardada.nay, em: guardada.em })
    }
    const recalcular = () => {
      let pedido = emAndamento.get(org)
      if (!pedido) {
        pedido = calcular(org)
          .then((r) => { guardadas.set(org, { em: Date.now(), ...r }); return r })
          .finally(() => emAndamento.delete(org))
        emAndamento.set(org, pedido)
      }
      return pedido
    }
    /*
     * RESPONDE NA HORA (29/09, Pedro: "cliques rápidos sem bugar"): a consulta
     * à Nay leva até 8 s. Com uma cópia vencida na mão, ela volta já e a conta
     * nova roda por trás -- a próxima leitura pega a fresca. Só a primeira
     * leitura (e o `?fresco=1` de quem acabou de mexer) espera a conta.
     *
     * `?esperar=1` (04/10, a Rayssa: "não estava chegando mensagem"): é a
     * leitura de fundo, de minuto em minuto, que não trava clique nenhum. Ela
     * espera a conta nova em vez de levar a vencida. Antes a tela mostrava
     * sempre a conta da leitura ANTERIOR: a conversa que a Nay passava para a
     * Rayssa só entrava na aba dela 1 a 2 minutos depois. A carga é a mesma
     * (uma conta por leitura vencida); muda só quem recebe o resultado.
     */
    const esperar = req.nextUrl.searchParams.get('esperar') === '1'
    if (guardada && !fresco && !esperar) {
      void recalcular().catch((e) => console.error('[parceria/marcas] recálculo', e?.message || e))
      return Response.json({ marcas: guardada.marcas, nay: guardada.nay, em: guardada.em, vencida: true })
    }
    const { marcas, nay } = await recalcular()
    return Response.json({ marcas, nay, em: Date.now() })
  } catch (err: any) {
    console.error('[parceria/marcas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a Nay.')
  }
}
