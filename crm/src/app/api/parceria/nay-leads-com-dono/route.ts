/**
 * OS DONOS COM QUEM A NAY LEADS ESTÁ CONVERSANDO PELA PARCERIA (Pedro, 24/10/2026; migração 492).
 *
 *   GET /api/parceria/nay-leads-com-dono     { donos: { <8 últimos dígitos>: { nome, motivo, ate } } }
 *
 * A Nay Leads fala com o proprietário pelo número em que ele já conversa conosco; quando é a Parceria, a conversa dele
 * fica roxa na lista com a etiqueta "Nay olx(leads) conversando" (LeadListItem). A marca vale 24 h desde a última
 * mensagem dela. O banco é o da Nay, pelo papel do CRM (nay_disparo), que só executa a função.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { fim8 } from '@/lib/olxClientes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT * FROM crm_nay_leads_com_dono()')
    const donos: Record<string, { nome: string | null; motivo: string | null; ate: string }> = {}
    for (const d of r.rows as any[]) {
      const k = fim8(d.telefone)
      if (k.length === 8) donos[k] = { nome: d.nome || null, motivo: d.motivo || null, ate: d.ate }
    }
    return Response.json({ donos, em: Date.now() })
  } catch (err: any) {
    console.error('[parceria/nay-leads-com-dono]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as conversas da Nay Leads com os donos.')
  }
}
