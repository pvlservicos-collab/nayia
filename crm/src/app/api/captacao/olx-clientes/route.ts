/**
 * OS CLIENTES DA OLX DA ABA CAPTAÇÃO (Pedro, 16/10/2026; migração 385). Ver src/lib/olxClientes.ts.
 *
 *   GET  /api/captacao/olx-clientes                       { clientes: { <8 últimos dígitos>: ClienteOlx } }
 *   POST /api/captacao/olx-clientes  { telefone, etapa }   a equipe muda a etapa (crm_olx_cliente_etapa)
 *
 * O banco é o da Nay (privado.olx_lead_whatsapp), pelo papel do CRM (nay_disparo), que só executa as duas funções.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { ehEtapaOlx, fim8, type ClienteOlx } from '@/lib/olxClientes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT * FROM crm_olx_clientes_etapas()')
    const clientes: Record<string, ClienteOlx> = {}
    for (const l of r.rows as any[]) {
      const k = fim8(l.telefone)
      if (k.length !== 8) continue
      clientes[k] = { etapa: l.etapa, nome: l.nome || null, codigo: l.codigo == null ? null : Number(l.codigo),
                      quer_visita: !!l.quer_visita, humano: !!l.humano,
                      // 520: o passo da Nay (a barrinha) e a finalidade (a etiqueta Locação/Venda)
                      origem: l.origem || null, passo: Number(l.passo || 0), finalidade: l.finalidade || null }
    }
    return Response.json({ clientes, em: Date.now() })
  } catch (err: any) {
    console.error('[captacao/olx-clientes]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os clientes da OLX.')
  }
}

export async function POST(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const telefone = String(corpo?.telefone || '')
    if (fim8(telefone).length !== 8 || !ehEtapaOlx(corpo?.etapa)) return apiError(400, 'Diga o telefone e uma etapa válida.')
    const r = await naydb().query('SELECT crm_olx_cliente_etapa($1, $2) AS ok', [telefone, corpo.etapa])
    if (!r.rows[0]?.ok) return apiError(404, 'Este telefone não é de um cliente da OLX.')
    return Response.json({ ok: true })
  } catch (err: any) {
    console.error('[captacao/olx-clientes] etapa', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mudar a etapa.')
  }
}
