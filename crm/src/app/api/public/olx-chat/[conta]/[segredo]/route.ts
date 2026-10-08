/**
 * POST /api/public/olx-chat/<conta>/<segredo> -- A OLX ENTREGA UMA MENSAGEM DO CHAT (Pedro, 08/10/2026).
 *
 * É o endereço que registramos na OLX para cada conta (`proprietarios`, `corretores`) com
 * POST /autoservice/v1/chat. A OLX chama aqui a cada mensagem do chat da conta:
 *
 *   { chatId, message, senderType, email, name, phone, messageTimestamp, messageId, origin, listId }
 *
 * A OLX NÃO ASSINA A CHAMADA. Quem prova que é ela é o `<segredo>` do caminho, que só nós e a OLX
 * conhecemos (um por conta, guardado no banco da Nay). O IP de onde veio fica gravado em cada
 * mensagem (o dela é 54.162.151.93) -- gravado, não exigido: se a OLX trocar de IP, a mensagem do
 * cliente não pode se perder por isso.
 *
 * Respondemos 200 quando a mensagem ficou gravada (inclusive a repetida, que não duplica), 401 com
 * o segredo errado e 500 se o banco falhou -- para a OLX tentar de novo, se ela tentar.
 * Ver crm/docs/olx/chat-da-olx.md e a migração 314.
 */
import { NextRequest } from 'next/server'
import { receberDaOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest, { params }: { params: Promise<{ conta: string; segredo: string }> }) {
  const { conta, segredo } = await params
  const ip = (req.headers.get('x-forwarded-for') || '').split(',')[0].trim() || null
  const texto = await req.text().catch(() => '')
  let corpo: unknown
  try { corpo = texto ? JSON.parse(texto) : null } catch {
    return Response.json({ ok: false, erro: 'O corpo não é um JSON válido.' }, { status: 400 })
  }
  try {
    const r = await receberDaOlx(conta, segredo, corpo, ip)
    if (r.ok) return Response.json({ ok: true, novo: !!r.novo })
    if (r.codigo_erro === 'nao_autorizado') return Response.json({ ok: false, erro: 'Não autorizado.' }, { status: 401 })
    if (r.codigo_erro === 'formato' || r.codigo_erro === 'grande_demais') {
      return Response.json({ ok: false, erro: r.erro || 'Mensagem fora do formato.' }, { status: 400 })
    }
    console.error('[olx-chat] o banco recusou', conta, r.codigo_erro, r.erro)
    return Response.json({ ok: false, erro: 'Não consegui gravar agora.' }, { status: 500 })
  } catch (err: any) {
    console.error('[olx-chat]', conta, err?.message || err)
    return Response.json({ ok: false, erro: 'Não consegui gravar agora.' }, { status: 500 })
  }
}

export async function GET() {
  return Response.json({ ok: false, erro: 'Use POST.' }, { status: 405 })
}
