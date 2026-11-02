/**
 * GET /api/corretores?dias=30 -- os corretores parceiros para Configurações >
 * Corretores (Pedro, 29/09/2026): "fica em um menu lá em configurações de
 * corretores, ele vê os que mais interagem, mais agendam e os documentos
 * salvos lá".
 *
 * Corretor = conversa da Parceria que a Nay reconhece como corretor (e não é da
 * equipe). Para cada um, no período: mensagens dele, as nossas, a última
 * conversa, visitas pedidas e realizadas (banco da Nay) e os documentos da
 * pasta dele.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { marcasDaNay, visitasDaNay } from '@/lib/nayLeitura'
import { conversaPorChave, conversasDaParceria } from '@/lib/conversasDaParceria'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId
    const dias = Math.min(365, Math.max(1, Number(req.nextUrl.searchParams.get('dias')) || 30))
    const desde = new Date(Date.now() - dias * 86400000)

    const conversas = await conversasDaParceria(org)
    const marcas = await marcasDaNay(conversas.map((c) => c.telefone || '').filter(Boolean))
    const corretores = conversas.filter((c) => {
      const m = c.telefone ? marcas.get(c.telefone) : undefined
      return m?.corretor && !m.equipe
    })
    if (!corretores.length) return Response.json({ corretores: [], dias })
    const ids = JSON.stringify(corretores.map((c) => c.id))

    const [mensagens, documentos, visitas] = await Promise.all([
      db.execute(sql`
        SELECT a.lead_id::text AS id,
               count(*) FILTER (WHERE a.metadata->>'direction' = 'inbound' AND a.created_at >= ${desde.toISOString()}::timestamptz) AS dele,
               count(*) FILTER (WHERE a.metadata->>'direction' = 'outbound' AND a.created_at >= ${desde.toISOString()}::timestamptz) AS nossas,
               max(a.created_at) FILTER (WHERE a.metadata->>'direction' = 'inbound') AS ultima
          FROM lead_activities a
         WHERE a.lead_id IN (SELECT (jsonb_array_elements_text(${ids}::jsonb))::uuid) AND a.type = 'whatsapp'
         GROUP BY a.lead_id`),
      db.execute(sql`
        SELECT lead_id::text AS id, count(*) AS n FROM corretor_documentos
         WHERE apagado_em IS NULL AND lead_id IN (SELECT (jsonb_array_elements_text(${ids}::jsonb))::uuid)
         GROUP BY lead_id`),
      visitasDaNay(desde.toISOString().slice(0, 10), null),
    ])
    // CONTRATOS (221, Pedro 30/09: "contratos fechados"): fechamento que a Rayssa
    // concluiu no período; e o que está em andamento agora
    const contratos = new Map<string, { fechados: number; andamento: number }>()
    try {
      const r = await naydb().query('SELECT * FROM crm_fechamentos_por_telefone($1::text[], $2::timestamptz)',
        [corretores.map((c) => c.telefone).filter(Boolean), desde.toISOString()])
      for (const l of r.rows) contratos.set(l.telefone, { fechados: Number(l.fechados) || 0, andamento: Number(l.em_andamento) || 0 })
    } catch (err: any) {
      console.error('[corretores] contratos', err?.message || err)
    }
    // 02/11 (Pedro, 562): quantas vezes ele mesmo pediu imóvel pela página /imoveis (o "me envia", com o número dele)
    const pediu = new Map<string, { pedidos: number; enviados: number; distintos: number; ultimo: string | null }>()
    try {
      const r = await naydb().query('SELECT * FROM crm_me_envia_por_telefone($1::text[], $2::timestamptz)',
        [corretores.map((c) => c.telefone).filter(Boolean), desde.toISOString()])
      for (const l of r.rows) pediu.set(l.telefone, { pedidos: Number(l.pedidos) || 0, enviados: Number(l.imoveis_enviados) || 0,
        distintos: Number(l.imoveis_distintos) || 0, ultimo: l.ultimo ? new Date(l.ultimo).toISOString() : null })
    } catch (err: any) {
      console.error('[corretores] me-envia', err?.message || err)    // antes da 562 no banco: segue sem a contagem
    }
    const porId = new Map<string, any>()
    for (const l of mensagens.rows as any[]) porId.set(l.id, l)
    const docs = new Map<string, number>((documentos.rows as any[]).map((l) => [l.id, Number(l.n)]))

    // visita -> conversa do corretor, pelas chaves da Nay (como /api/parceria/visitas)
    const porChave = conversaPorChave(conversas)
    const visitasDo = new Map<string, { pedidas: number; realizadas: number; abertas: number }>()
    for (const v of visitas) {
      const quando = new Date(v.quando || v.criadoEm || 0)
      if (quando < desde) continue
      const conversa = v.corretorChaves.map((ch) => porChave.get(ch)).find(Boolean)
      if (!conversa) continue
      const c = visitasDo.get(conversa.id) || { pedidas: 0, realizadas: 0, abertas: 0 }
      c.pedidas++
      if (v.estado === 'realizada' || v.estado === 'encerrada') c.realizadas++
      if (v.aberta && v.estado !== 'realizada') c.abertas++
      visitasDo.set(conversa.id, c)
    }

    const saida = corretores.map((c) => {
      const m = marcas.get(c.telefone!)!
      const msg = porId.get(c.id)
      const vis = visitasDo.get(c.id) || { pedidas: 0, realizadas: 0, abertas: 0 }
      return {
        leadId: c.id,
        nome: c.titulo || m.corretorNome || c.telefone,
        nomeNoCadastro: m.corretorNome,
        telefone: c.telefone,
        creci: m.creci,
        avatar: c.avatar,
        etapa: m.etapa,
        mensagensDele: Number(msg?.dele || 0),
        mensagensNossas: Number(msg?.nossas || 0),
        ultimaMensagem: msg?.ultima ? new Date(msg.ultima).toISOString() : null,
        visitasPedidas: vis.pedidas,
        visitasRealizadas: vis.realizadas,
        visitasAbertas: vis.abertas,
        documentos: docs.get(c.id) || 0,
        contratosFechados: contratos.get(c.telefone!)?.fechados ?? 0,
        fechamentoEmAndamento: contratos.get(c.telefone!)?.andamento ?? 0,
        pedidosNaPagina: pediu.get(c.telefone!)?.pedidos ?? 0,
        imoveisPedidosNaPagina: pediu.get(c.telefone!)?.enviados ?? 0,
        ultimoPedidoNaPagina: pediu.get(c.telefone!)?.ultimo ?? null,
      }
    })
    return Response.json({ corretores: saida, dias })
  } catch (err: any) {
    console.error('[corretores]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a lista de corretores.')
  }
}
