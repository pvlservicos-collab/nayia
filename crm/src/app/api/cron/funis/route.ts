/**
 * POST /api/cron/funis -- os funis andam sozinhos (ver src/lib/funis.ts).
 *
 * Chamada a cada minuto pelo cron do servidor (/etc/cron.d/crm-funis), de
 * dentro do container, com `x-cron-segredo` = CRON_SEGREDO -- o mesmo da
 * conferência com a Nay. Sem ele, 401.
 */
import { NextRequest } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { sincronizarFunis } from '@/lib/funis'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 300

function segredoConfere(veio: string | null): boolean {
  const certo = process.env.CRON_SEGREDO || ''
  if (!certo || !veio) return false
  const a = Buffer.from(certo)
  const b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

export async function POST(req: NextRequest) {
  if (!segredoConfere(req.headers.get('x-cron-segredo'))) return new Response('não autorizado', { status: 401 })
  const [linha] = await db
    .select({ org: integrations.organizationId })
    .from(integrations)
    .where(and(eq(integrations.type, 'whatsapp_zapi'), isNull(integrations.deletedAt)))
    .limit(1)
  if (!linha) return Response.json({ erro: 'sem a linha da Parceria' }, { status: 404 })
  try {
    const r = await sincronizarFunis(linha.org)
    if (!r) return Response.json({ ocupado: true }, { status: 202 })
    if (r.captacao.movidos || r.parceria.movidos) console.log('[funis]', JSON.stringify(r))
    return Response.json(r)
  } catch (err: any) {
    console.error('[funis] falhou', err?.message || err)
    return Response.json({ erro: err?.message || 'falhou' }, { status: 500 })
  }
}
