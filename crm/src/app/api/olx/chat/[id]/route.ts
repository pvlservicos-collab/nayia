/**
 * UMA CONVERSA DA OLX (Pedro, 08/10/2026).
 *
 *   GET  /api/olx/chat/<id>?conta=...   as mensagens, na ordem; abrir a conversa zera as não lidas
 *   POST /api/olx/chat/<id>             { conta, texto }  ->  manda a resposta pelo chat da OLX
 *
 * A resposta só é gravada como enviada se a OLX aceitar (HTTP 200 em /autoservice/v1/chat/send). Se ela
 * recusar, a tela recebe o motivo e o texto continua na caixa -- nada de "enviada" que não saiu.
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { ehContaOlx, marcarLidoOlx, mensagensDoChatOlx, responderNoChatOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const idDoChat = (v: string) => (/^\d{1,12}$/.test(v) ? Number(v) : null)
const MAXIMO = 2000

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    await authenticateRequest(req)
    const conta = req.nextUrl.searchParams.get('conta')
    const chat = idDoChat((await params).id)
    if (!ehContaOlx(conta) || !chat) return apiError(400, 'Conversa inválida.')
    const mensagens = await mensagensDoChatOlx(conta, chat)
    if (req.nextUrl.searchParams.get('lido') !== '0') await marcarLidoOlx(conta, chat).catch(() => {})
    return Response.json({ mensagens, em: Date.now() })
  } catch (err: any) {
    console.error('[olx/chat/id]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a conversa.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM responde no chat da OLX.')
    const corpo = await req.json().catch(() => ({} as any))
    const conta = corpo?.conta
    const chat = idDoChat((await params).id)
    if (!ehContaOlx(conta) || !chat) return apiError(400, 'Conversa inválida.')
    const texto = String(corpo?.texto ?? '').trim()
    if (!texto) return apiError(400, 'Escreva a mensagem.')
    if (texto.length > MAXIMO) return apiError(400, `A mensagem passou de ${MAXIMO} caracteres.`)

    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const quem = perfil?.nome?.trim() || 'alguém no CRM'
    const r = await responderNoChatOlx(conta, chat, texto, quem)
    return Response.json({ ok: true, messageId: r.messageId })
  } catch (err: any) {
    console.error('[olx/chat/id] envio', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar a mensagem.')
  }
}
