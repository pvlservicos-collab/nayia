import { NextRequest, NextResponse } from 'next/server'
import { processEvolutionMessage, logDiagnostic } from '@/lib/evolutionInbound'

// Eventos "message*" que não sejam messages.upsert/send.message (já tratados) e não
// estejam nessa lista são candidatos a mais algum formato desconhecido, então valem
// registro. messages.update é recibo de entrega/leitura — evento normal e frequente,
// nunca teria conteúdo extraível; sem essa exclusão ele sozinho gerava 393 das 395
// linhas já gravadas na tabela (puro ruído, tabela sem rotina de limpeza).
const KNOWN_NOISE_EVENTS = new Set(['messages.update', 'messages.delete', 'messages.reaction'])

export async function POST(req: NextRequest) {
  try {
    const orgId = req.nextUrl.searchParams.get('org_id')
    if (!orgId) return NextResponse.json({ ok: false, error: 'org_id ausente' }, { status: 400 })

    const body = await req.json()

    // Mensagem enviada direto do WhatsApp (Web/celular, fora do CRM) chega num evento
    // diferente — "send.message" — do que mensagem recebida ou sincronizada, que usa
    // "messages.upsert". Confirmado com payload real capturado pelo log de diagnóstico
    // (ver nota acima): o handler só tratava messages.upsert, então TODA mensagem
    // (texto ou mídia) mandada direto do celular era descartada em silêncio — nunca
    // aparecia no CRM. O formato de "data" dos dois eventos é o mesmo (key/message/
    // messageTimestamp), então o resto do processamento funciona sem mudança.
    //
    // Investigação de 2026-07-13 (confirmada comparando com o histórico da própria
    // Evolution API via /chat/findMessages): uma foto com legenda mandada direto do
    // WhatsApp (fromMe) sumiu sem nenhum rastro. O payload em si era um imageMessage
    // normal, perfeitamente extraível — mas chegou como evento "messages.update" em
    // vez de "messages.upsert"/"send.message". É o comportamento real do Baileys pra
    // mídia de saída: o "eco" da mensagem some antes do upload terminar e reaparece
    // via update, não upsert. Como messages.update sempre foi tratado como puro ruído
    // de recibo de entrega/leitura (KNOWN_NOISE_EVENTS), o payload inteiro (imagem +
    // legenda) foi descartado em silêncio total. Agora: messages.update que carrega
    // `data.message` de verdade (não só um `{status}` de recibo) é tratado como
    // mensagem de conteúdo real, não como ruído.
    const hasRealContent = !!body.data?.message && Object.keys(body.data.message).length > 0
    const isRecognizedMessageEvent =
      body.event === 'messages.upsert' ||
      body.event === 'send.message' ||
      (body.event === 'messages.update' && hasRealContent)

    if (!isRecognizedMessageEvent) {
      if (
        typeof body.event === 'string' &&
        body.event.toLowerCase().includes('message') &&
        !KNOWN_NOISE_EVENTS.has(body.event)
      ) {
        await logDiagnostic('unhandled_message_event', orgId, body)
      }
      return NextResponse.json({ ok: true, skipped: true })
    }

    const result = await processEvolutionMessage(orgId, body.data, { instance: body.instance, sender: body.sender })

    if (result.status === 'created') {
      return NextResponse.json({ ok: true, activityId: result.activityId })
    }
    return NextResponse.json({ ok: true, skipped: result.reason })
  } catch (err: any) {
    console.error('[evolution webhook]', err)
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 })
  }
}

// Evolution API uses POST for webhook verification too
export async function GET() {
  return NextResponse.json({ ok: true, message: 'Evolution webhook endpoint active' })
}
