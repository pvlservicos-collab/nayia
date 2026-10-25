/**
 * O PIPELINE DOS LEADS DA ABA LEADS (Pedro, 24/10/2026; migração 491). Ver src/components/Chat/PipelineDosLeads.tsx.
 *
 *   GET /api/captacao/pipeline-leads?de=AAAA-MM-DD&ate=AAAA-MM-DD   { leads: [...] }   (dias de Manaus)
 *
 * O banco é o da Nay (privado.olx_lead_whatsapp), pelo papel do CRM (nay_disparo), que só executa a função.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { diaEmManaus } from '@/lib/fusoDeManaus'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DIA = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const q = req.nextUrl.searchParams
    const ate = DIA.test(q.get('ate') || '') ? q.get('ate')! : diaEmManaus()
    const de = DIA.test(q.get('de') || '') ? q.get('de')! : diaEmManaus(new Date(Date.now() - 30 * 86400_000))
    const r = await naydb().query('SELECT * FROM crm_leads_pipeline($1::date, $2::date)', [de, ate])
    return Response.json({ de, ate, leads: r.rows })
  } catch (err: any) {
    console.error('[captacao/pipeline-leads]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o pipeline dos leads.')
  }
}
