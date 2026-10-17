/**
 * O CONTADOR DA API OFICIAL (Pedro, 16/10/2026: "por contador de mensagens em cima do número de API oficial para
 * sabermos quanto já disparamos, e quanto já mandamos de mensagem de serviço ... para ver se já estouramos as mil
 * grátis e quanto estamos gastando").
 *
 *   GET /api/oficial/custo-meta -> { mes, moeda, modelos: {total, pagos, gratis}, servico, custo, categorias: [...] }
 *
 * Os números são os da própria Meta (pricing_analytics da conta, do dia 1º do mês até agora, na moeda da conta),
 * não uma conta nossa. Desde 1º/07/2025 a Meta cobra POR MODELO ENTREGUE (marketing, utilidade, autenticação); a
 * mensagem de serviço (resposta dentro das 24 h) e o modelo de utilidade dentro da janela são grátis -- a franquia de
 * 1.000 conversas grátis por mês acabou. A Meta avisa que o número é aproximado (a fatura manda). Guardado 5 min.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { credencialMeta, graph } from '@/lib/metaTemplates'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const guardado = new Map<string, { em: number; corpo: unknown }>()
const ROTULO: Record<string, string> = {
  MARKETING: 'Marketing', MARKETING_LITE: 'Marketing', UTILITY: 'Utilidade', AUTHENTICATION: 'Autenticação',
  AUTHENTICATION_INTERNATIONAL: 'Autenticação', SERVICE: 'Serviço', REFERRAL_CONVERSION: 'Anúncio',
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const ja = guardado.get(auth.organizationId)
    if (ja && Date.now() - ja.em < 5 * 60_000) return Response.json(ja.corpo)

    const cred = await credencialMeta(auth.organizationId)
    if (!cred) return apiError(400, 'A API oficial não está configurada no CRM.')
    // o mês de Manaus: do dia 1º 00:00 (-04:00) até agora
    const agora = new Date()
    const manaus = new Date(agora.getTime() - 4 * 3600_000)
    const inicio = Math.floor(Date.UTC(manaus.getUTCFullYear(), manaus.getUTCMonth(), 1, 4) / 1000)
    const fim = Math.floor(agora.getTime() / 1000)

    const [conta, r] = await Promise.all([
      graph(cred, `${cred.wabaId}?fields=currency`),
      graph(cred, `${cred.wabaId}?fields=pricing_analytics.start(${inicio}).end(${fim}).granularity(DAILY).dimensions(PRICING_CATEGORY,PRICING_TYPE)`),
    ])
    const por = new Map<string, { rotulo: string; volume: number; pagos: number; custo: number }>()
    let servico = 0, pagos = 0, gratis = 0, custo = 0
    for (const bloco of r?.pricing_analytics?.data || []) {
      for (const p of bloco?.data_points || []) {
        const vol = Number(p.volume) || 0
        const c = Number(p.cost) || 0
        const cat = String(p.pricing_category || '')
        custo += c
        if (cat === 'SERVICE') { servico += vol; continue }
        const pago = String(p.pricing_type || '') === 'REGULAR'
        if (pago) pagos += vol; else gratis += vol
        const rot = ROTULO[cat] || cat || 'Outros'
        const x = por.get(rot) || { rotulo: rot, volume: 0, pagos: 0, custo: 0 }
        x.volume += vol; if (pago) x.pagos += vol; x.custo += c
        por.set(rot, x)
      }
    }
    const corpo = {
      mes: manaus.toLocaleDateString('pt-BR', { month: 'long', timeZone: 'UTC' }),
      moeda: String(conta?.currency || 'BRL'),
      modelos: { total: pagos + gratis, pagos, gratis },
      servico,
      custo: Math.round(custo * 100) / 100,
      categorias: [...por.values()].sort((a, b) => b.volume - a.volume)
        .map((x) => ({ ...x, custo: Math.round(x.custo * 100) / 100 })),
      lidoEm: agora.toISOString(),
    }
    guardado.set(auth.organizationId, { em: Date.now(), corpo })
    return Response.json(corpo)
  } catch (err: any) {
    console.error('[oficial/custo-meta]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os números da Meta.')
  }
}
