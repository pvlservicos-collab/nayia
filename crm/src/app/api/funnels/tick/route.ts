import { processTick } from '@/lib/funnel-engine'

/**
 * GET/POST /api/funnels/tick
 * Processa todas as execuções de funis pendentes (esperas vencidas e checagens
 * de "Respondeu?"). Sem autenticação (uso interno) — chamado periodicamente
 * pelo Cron Job do Vercel (ver vercel.json) e também aceita POST manual.
 */
async function tick() {
  try {
    const result = await processTick()
    return Response.json({ status: 'ok', ...result })
  } catch (err: any) {
    return Response.json({ status: 'error', message: err.message || 'Erro interno.' }, { status: 500 })
  }
}

export const GET = tick
export const POST = tick
