/**
 * OS CONTATOS RELACIONADOS DO WHATSAPP LEADS (Pedro, 29/10/2026; nayia 517): "o lead perguntou algo e a Nay foi em outro
 * contato perguntar ... ele deve ficar em uma aba embaixo do contato de quem perguntou, tipo um contato relacionado".
 *
 *   GET /api/captacao/relacionados   { pares: [{ cliente, contato, em, motivos, codigos }] }   (8 últimos dígitos)
 *
 * O par sai do banco da Nay (crm_contatos_relacionados): o que a Nay Leads mandou pelo 8595 a outra pessoa em nome do
 * lead (dúvida ao dono, visita ao corretor, lembrete) e as dúvidas da 512. A lista (LeadList) aninha o contato.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT cliente, contato, em, motivos, codigos FROM crm_contatos_relacionados()')
    return Response.json({ pares: r.rows, em: Date.now() })
  } catch (err: any) {
    console.error('[captacao/relacionados]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os contatos relacionados.')
  }
}
