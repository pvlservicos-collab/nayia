import { NextRequest } from 'next/server'
import { db } from '@/lib/db'
import { funnelClickEvents } from '@/lib/schema'
import { eq } from 'drizzle-orm'

/**
 * GET /f/[token]
 * Link rastreável de um funil de mensagens: registra o clique (1ª vez) e
 * redireciona para a URL de destino configurada no bloco de mensagem.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params

  const [click] = await db.select().from(funnelClickEvents).where(eq(funnelClickEvents.token, token)).limit(1)
  if (!click) return new Response('Not found', { status: 404 })

  if (!click.clicked) {
    await db.update(funnelClickEvents).set({ clicked: true, clickedAt: new Date() }).where(eq(funnelClickEvents.id, click.id))
  }

  return Response.redirect(click.targetUrl, 302)
}
