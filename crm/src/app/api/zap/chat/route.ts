/**
 * GET /api/zap/chat -- as conversas do Chat Zap (574): os leads do Canal Pro (ZAP, Viva Real, OLX), um por pessoa.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT crm_zap_chats() AS c')
    return Response.json({ chats: r.rows[0]?.c ?? [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os leads do ZAP.')
  }
}
