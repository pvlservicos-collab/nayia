/**
 * GET /api/parceria/fechamento/autopreencher?lead=<id>&tipo=locacao|venda
 * -> { tipo, valores, origem, faltam }
 * O checklist a partir da conversa (Pedro, 30/09/2026: "escolher um contato que
 * já mandou as informações e o site preenche o checklist sozinho"): os dados que
 * vieram escritos depois do checklist (ou nos últimos 30 dias), o corretor pelo
 * próprio lead e as caixinhas dos documentos que já chegaram. Só sugere: a tela
 * preenche e a Rayssa confere.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import type { TipoChecklist } from '@/lib/checklistFechamento'
import { camposQueFaltam, lerCampos, marcaDoDocumento } from '@/lib/fechamentoDocumentos'
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
    const tipo: TipoChecklist = pedido === 'venda' || pedido === 'locacao' ? pedido : naNay.tipo ?? 'locacao'

    const atividades = await atividadesDoLead(auth.organizationId, lead.id)
    const desde = Date.parse(naNay.enviadoEm || naNay.desde || '') || Date.now() - 30 * 86_400_000
    const mensagens = atividades
      .filter((a) => !a.midia && a.direcao === 'recebida' && a.texto.trim() && Date.parse(a.quando) >= desde - 3_600_000)
      .map((a) => ({ activityId: a.id, texto: a.texto }))
    const { valores, origem } = lerCampos(mensagens, tipo)

    // o corretor é a própria conversa da Parceria
    if (!valores.corretor_nome && lead.nome) valores.corretor_nome = lead.nome
    if (!valores.corretor_telefone && lead.telefone) valores.corretor_telefone = lead.telefone

    // as caixinhas dos documentos que já chegaram (escolha da Rayssa ou automático)
    for (const it of await itensDoFechamento(atividades, lead.id, tipo)) {
      if (!it.documento) continue
      const marca = marcaDoDocumento(it.documento.chave, tipo, it.papel)
      if (marca) {
        valores[marca] = true
        origem[marca] = { activityId: it.activityId, trecho: it.documento.rotulo }
      }
    }
    return Response.json({ tipo, valores, origem, faltam: camposQueFaltam(tipo, valores) })
  } catch (err: any) {
    console.error('[fechamento autopreencher]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a conversa.')
  }
}
