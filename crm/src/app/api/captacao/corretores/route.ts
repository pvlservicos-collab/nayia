/**
 * GET /api/captacao/corretores -> { fins: ["12345678", ...] }
 *
 * Os corretores do WhatsApp Leads (crm_captacao_corretores, 526): quem disse que é corretor, tem CRECI, é da equipe,
 * acompanha visita... (os 8 últimos dígitos). Pedro, 30/10/2026: o botão "Proprietários e corretores" da lista do Leads
 * separa os dois -- corretor a Nay atende, proprietário não. A mesma leitura que a lista de donos usa (cache de 10 min).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { corretoresDaCaptacao } from '@/app/api/captacao/donos/route'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    return Response.json({ fins: [...(await corretoresDaCaptacao())] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os corretores do Leads.')
  }
}
