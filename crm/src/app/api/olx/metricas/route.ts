/**
 * GET /api/olx/metricas -- A TABELA DE MÉTRICAS dos anúncios da OLX (Pedro, 14/10/2026: "uma lista com os anúncios e
 * várias colunas, com os dados que a OLX compartilha ... a lista vai se atualizando por número maior de mensagens no
 * topo, mas eu clicando em cada coluna consigo ver ordenado por esse dado").
 *
 * Uma linha por anúncio (`crm_olx_metricas`, migração 369): conversas e mensagens do chat, os contatos que a OLX
 * avisa (WhatsApp, telefone, chat), dias no ar, situação na OLX. E o saldo do plano de cada conta conectada
 * (/autoupload/balance). VISUALIZAÇÕES a OLX não fornece pela API.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { metricasOlx, saldoDoPlanoOlx } from '@/lib/olxChat'
import { CONTAS_OLX } from '@/lib/olxChatTipos'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const [m, ...planos] = await Promise.all([metricasOlx(), ...CONTAS_OLX.map((c) => saldoDoPlanoOlx(c).catch(() => null))])
    return Response.json({ ...m, planos: CONTAS_OLX.map((c, i) => ({ conta: c, plano: planos[i] })).filter((p) => p.plano) })
  } catch (err: any) {
    console.error('[olx/metricas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as métricas da OLX.')
  }
}
