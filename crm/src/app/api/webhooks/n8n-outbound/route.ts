import { NextRequest } from 'next/server'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadActivities, integrationMessageLogs, organizations } from '@/lib/schema'
import { eq, sql } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { registrarEnvioNoCrm, type CanalDeEnvio } from '@/lib/registrarEnvio'

/**
 * POST /api/webhooks/n8n-outbound
 * Registra no CRM uma mensagem que o n8n já enviou pelo WhatsApp.
 *
 * Existe porque a Meta só avisa o que CHEGA: o que a Nay manda pela API oficial
 * não volta em webhook nenhum com o texto. Quem manda grava (Tel, 26/09/2026:
 * "tem que criar automaticamente toda mensagem enviada por nos no crm").
 *
 * DUAS COISAS ESTAVAM ERRADAS AQUI e ninguém tinha como notar:
 *
 *   1. a organização era uma constante '91a7f4af-…' do projeto anterior, que
 *      NÃO EXISTE neste banco. Qualquer chamada morria em violação de chave
 *      estrangeira -- e de fato `integration_message_logs` estava vazia, o que
 *      quer dizer que isto nunca funcionou uma vez.
 *   2. o lead nascia sem integração. As duas abas do chat filtram por linha, e
 *      `getLinhaWhatsapp` devolve null sem integração: o lead não aparecia em
 *      aba nenhuma. Invisível, sem erro.
 *
 * Agora a organização é a que existe, e `registrarEnvioNoCrm` amarra o lead à
 * linha por onde a mensagem saiu.
 *
 * Sem autenticação (uso interno, atrás do Traefik). Tolerante a payload
 * desformatado: aceita JSON inválido, array (usa o primeiro item), e tanto
 * { phone, content } quanto a resposta crua da API do WhatsApp.
 */

/** A organização da casa. Só existe uma; se um dia houver mais, o n8n manda o id. */
async function organizacaoAlvo(body: any): Promise<string> {
  const pedido = body?.organization_id
  if (typeof pedido === 'string' && pedido.length === 36) {
    const [org] = await db.select({ id: organizations.id }).from(organizations)
      .where(eq(organizations.id, pedido)).limit(1)
    if (org) return org.id
  }
  const [primeira] = await db.select({ id: organizations.id }).from(organizations).limit(1)
  if (!primeira) throw { status: 500, message: 'Nenhuma organização no banco.' }
  return primeira.id
}

export async function POST(req: NextRequest) {
  const raw = await req.text()

  let parsed: any = null
  let parseError: string | null = null
  try {
    parsed = raw ? JSON.parse(raw) : {}
  } catch (err: any) {
    parseError = `JSON inválido: ${err.message}`
  }

  const body = Array.isArray(parsed) ? (parsed[0] ?? {}) : (parsed ?? {})

  const rawPhone =
    body.phone ??
    body.wa_id ??
    body.contacts?.[0]?.wa_id ??
    body.contacts?.[0]?.input ??
    body.messages?.[0]?.from ??
    null

  const content =
    body.content ??
    body.text ??
    body.message ??
    body.messages?.[0]?.text?.body ??
    body.messages?.[0]?.template?.name ??
    null

  const phone = rawPhone != null ? String(rawPhone).replace(/\D/g, '') : ''
  const senderName = body.sender_name || body.contacts?.[0]?.profile?.name || null

  const whatsappMessageId =
    body.whatsapp_message_id ??
    body.messages?.[0]?.id ??
    body.message_id ??
    null

  const messageStatus =
    body.message_status ??
    body.messages?.[0]?.message_status ??
    null

  // Por qual linha saiu. O id da Cloud API começa com "wamid."; o n8n também
  // pode dizer na mão. Sem pista nenhuma, assume a oficial -- a Z-API já grava
  // o que ela mesma manda, pelo eco `fromMe` do `zapiInbound`. A captação
  // (Z-API, 8595-6408) só quando o n8n diz, porque o id dela é igual ao da
  // Parceria.
  const pedido = body.canal ?? body.channel
  const canal: CanalDeEnvio =
    pedido === 'whatsapp_zapi_captacao'
      ? 'whatsapp_zapi_captacao'
      : pedido === 'whatsapp_zapi' || body.zapi_message_id
        ? 'whatsapp_zapi'
        : 'whatsapp_cloud_official'

  let organizationId: string | null = null

  try {
    if (parseError) throw { status: 200, message: parseError }
    organizationId = await organizacaoAlvo(body)

    // Atualização de status ("delivered"/"read"), sem texto novo: só carimba a
    // mensagem que já está lá, sem criar lead nem atividade.
    if (!content && whatsappMessageId) {
      const [activity] = await db.select({
        id: leadActivities.id, leadId: leadActivities.leadId, metadata: leadActivities.metadata,
      })
        .from(leadActivities)
        .where(sql`${leadActivities.metadata}->>'whatsapp_message_id' = ${whatsappMessageId}`)
        .limit(1)

      if (activity) {
        await db.update(leadActivities)
          .set({ metadata: { ...(activity.metadata as object), whatsapp_status: messageStatus } })
          .where(eq(leadActivities.id, activity.id))
        await publishEvent(channels.leadActivities(activity.leadId), events.ACTIVITY_UPDATED, { id: activity.id })
      }

      await db.insert(integrationMessageLogs).values({
        organizationId,
        source: 'n8n',
        direction: 'outbound',
        phone: phone || null,
        content: null,
        leadId: activity?.leadId,
        status: 'success',
        payload: { raw, parsed },
      })

      return Response.json({ status: 'ok', updated: !!activity })
    }

    if (!phone) throw { status: 200, message: 'Não foi possível identificar o telefone (phone) na mensagem. Nenhum lead foi atualizado.' }
    if (!content) throw { status: 200, message: 'Não foi possível identificar o conteúdo (content) da mensagem. Nenhum lead foi atualizado.' }

    const registro = await registrarEnvioNoCrm({
      organizationId,
      telefone: phone,
      texto: String(content),
      canal,
      nomeSugerido: senderName,
      whatsappMessageId: canal === 'whatsapp_cloud_official' ? whatsappMessageId : null,
      zapiMessageId: canal !== 'whatsapp_cloud_official' ? (body.zapi_message_id ?? null) : null,
      origem: 'n8n',
      extraMetadata: { sender_name: senderName, whatsapp_status: messageStatus },
    })

    await db.insert(integrationMessageLogs).values({
      organizationId,
      source: 'n8n',
      direction: 'outbound',
      phone,
      content: String(content),
      leadId: registro.leadId,
      status: 'success',
      payload: { raw, parsed },
    })

    return Response.json({
      status: 'ok',
      lead_id: registro.leadId,
      activity_id: registro.activityId,
      linha: registro.linha,
      skipped: registro.duplicado ? 'duplicate' : undefined,
    })
  } catch (err: any) {
    if (organizationId) {
      await db.insert(integrationMessageLogs).values({
        organizationId,
        source: 'n8n',
        direction: 'outbound',
        phone: phone || null,
        content: content != null ? String(content) : null,
        status: 'error',
        error: err.message || 'Erro interno.',
        payload: { raw, parsed },
      }).catch(() => {})
    }
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
