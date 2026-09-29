/**
 * POST /api/webhooks/captacao-oficial
 * A Nay de captação responde pelo NÚMERO OFICIAL (8456-0874).
 *
 * Pedro, 28/09/2026: "a nay de captação vai agora conversar pelo número
 * oficial". O fluxo da captação (n8n, na srv1877774) sempre respondeu pela
 * Z-API. Para o número oficial, quem manda é o CRM, por dois motivos:
 *
 *   1. o token da Meta mora aqui (META_TOKEN no .env) e não sai daqui;
 *   2. a Meta não devolve em webhook o que a gente manda -- quem manda grava
 *      (`registrarEnvioNoCrm`), e é isso que põe a resposta da Nay na conversa
 *      da aba WhatsApp Oficial.
 *
 * O caminho de ida é o webhook da Meta (`/api/webhooks/facebook`), que repassa
 * para a captação o que chega no número oficial.
 *
 * Protegido por `x-captacao-segredo` = CAPTACAO_OFICIAL_SEGREDO (.env): o
 * /api/webhooks é público, e sem isso qualquer um mandaria mensagem pelo
 * número oficial. Sempre responde 200 com { ok, messageId, erro } -- o n8n
 * grava a falha ('Falhou') em vez de derrubar o laço de balões.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { getChannelAdapter } from '@/lib/channels/registry'
import { registrarEnvioNoCrm } from '@/lib/registrarEnvio'

export async function POST(req: NextRequest) {
  const segredo = process.env.CAPTACAO_OFICIAL_SEGREDO
  if (!segredo || req.headers.get('x-captacao-segredo') !== segredo) {
    return Response.json({ ok: false, erro: 'não autorizado', messageId: null }, { status: 401 })
  }

  const body = await req.json().catch(() => ({} as any))
  const telefone = String(body?.telefone ?? '').replace(/\D/g, '')
  const texto = String(body?.texto ?? '').trim()
  if (telefone.length < 12 || !texto) {
    return Response.json({ ok: false, erro: 'telefone ou texto faltando', messageId: null })
  }

  const [linha] = await db
    .select({ id: integrations.id, organizationId: integrations.organizationId })
    .from(integrations)
    .where(and(eq(integrations.type, 'whatsapp_cloud_official'), isNull(integrations.deletedAt)))
    .limit(1)
  if (!linha) return Response.json({ ok: false, erro: 'a linha oficial não existe', messageId: null })

  let messageId: string | null = null
  try {
    const r = await getChannelAdapter('whatsapp_cloud_official')
      .sendText(linha.organizationId, linha.id, telefone, texto, false)
    messageId = r.externalId || null
  } catch (err: any) {
    // Fora da janela de 24h a Meta recusa texto livre (só template). O erro
    // dela volta para o n8n, que grava a mensagem como 'Falhou'.
    console.error('[captacao-oficial] a resposta não saiu:', err?.message || err)
    return Response.json({ ok: false, erro: err?.message || 'erro ao enviar', messageId: null })
  }

  try {
    await registrarEnvioNoCrm({
      organizationId: linha.organizationId,
      telefone,
      texto,
      canal: 'whatsapp_cloud_official',
      whatsappMessageId: messageId,
      // 'ai_agent' e `automated`: resposta de robô não conta como atendimento
      // de gente na lista do chat (ver `manual` em /api/leads)
      origem: 'ai_agent',
      extraMetadata: { automated: true, agente: 'nay_captacao' },
    })
  } catch (err) {
    // A mensagem JÁ SAIU: falhar agora faria o n8n achar que não saiu.
    console.error('[captacao-oficial] saiu, mas não gravou no CRM:', err)
  }

  return Response.json({ ok: true, messageId })
}
