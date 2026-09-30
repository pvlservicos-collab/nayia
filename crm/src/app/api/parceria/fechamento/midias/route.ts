/**
 * GET /api/parceria/fechamento/midias?lead=<id>[&tipo=locacao|venda]
 * As mídias da conversa para a aba Fechamento (Pedro, 30/09/2026): cada uma com o
 * documento (a escolha da Rayssa ou o que a Nay identificou), o papel e o dono
 * (corretor/cliente), mais o catálogo da lista suspensa, na ordem e com o que é
 * exigido no tipo do fechamento. Regras em lib/fechamentoDocumentos.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { catalogoPara } from '@/lib/fechamentoDocumentos'
import { atividadesDoLead, fechamentoNaNay, itensDoFechamento, leadDoFechamento } from '@/lib/fechamentoServidor'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const lead = await leadDoFechamento(auth.organizationId, req.nextUrl.searchParams.get('lead') || '')
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    const naNay = await fechamentoNaNay(lead.telefone)
    const pedido = req.nextUrl.searchParams.get('tipo')
    const tipo = pedido === 'venda' || pedido === 'locacao' ? pedido : naNay.tipo
    const itens = await itensDoFechamento(await atividadesDoLead(auth.organizationId, lead.id), lead.id, tipo)
    return Response.json({
      lead,
      checklist: { tipo: naNay.tipo, enviadoEm: naNay.enviadoEm },
      catalogo: catalogoPara(tipo ?? 'locacao'),
      itens,
    })
  } catch (err: any) {
    console.error('[fechamento mídias]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as mídias da conversa.')
  }
}
