import { after } from 'next/server'
import { db } from '@/lib/db'
import { leads, leadActivities, integrations, pipelineStages, webhookLogs } from '@/lib/schema'
import { eq, and, isNull, asc, ilike, inArray } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { dispatchOutboundWebhook } from '@/lib/outbound-webhook'
import { downloadEvolutionMedia, fetchEvolutionProfilePicture } from '@/lib/evolution'
import { isUniqueViolation } from '@/lib/db-helpers'
import { notifyInboundMessage } from '@/lib/push'
import { avisarGrupoRespostaAutomacao } from '@/lib/avisoGrupo'
import { telefoneVariantes, telefoneCanonico } from '@/lib/leadSources'

// Processamento de uma mensagem Evolution/Baileys já reconhecida como conteúdo real
// (não recibo de entrega/leitura) — compartilhado entre o webhook em tempo real
// (src/app/api/webhooks/evolution/route.ts) e a reconciliação periódica
// (src/app/api/cron/evolution-reconcile/route.ts). Ambos alimentam essa função com o
// mesmo formato de `data` (key/message/messageTimestamp/pushName/instanceId) — o
// webhook pega direto do payload recebido, a reconciliação pega de
// `/chat/findMessages` da própria Evolution API (mesmo shape).

// DIAGNÓSTICO TEMPORÁRIO (2026-07-10, causa raiz do albumMessage confirmada em
// 2026-07-11; causa raiz do messages.update-com-conteúdo confirmada em 2026-07-13 —
// ver unwrapMessage/albumMessage e o isRecognizedMessageEvent no route.ts): mantido
// pra pegar formatos de mensagem ainda não mapeados. Sempre aguardado (await) — numa
// function serverless a resposta podia finalizar antes do INSERT completar, perdendo
// o diagnóstico exatamente no caso que mais importava capturar.
export async function logDiagnostic(reason: string, orgId: string, body: any) {
  try {
    await db.insert(webhookLogs).values({ payload: { reason, org_id: orgId, body } })
  } catch (err) {
    console.error('[evolution webhook] diagnostic log failed', err)
  }
}

// WhatsApp/Baileys embrulha o conteúdo real dentro de "containers" pra mensagem
// efêmera (some após X tempo), "ver uma vez" e documento-com-legenda. Sem desembrulhar,
// extractMessage não reconhecia nada desses casos e a mensagem inteira sumia do CRM sem
// nenhum rastro — confirmado em produção pra foto enviada direto do WhatsApp (fromMe).
function unwrapMessage(msg: any): any {
  if (msg?.ephemeralMessage?.message) return unwrapMessage(msg.ephemeralMessage.message)
  if (msg?.viewOnceMessage?.message) return unwrapMessage(msg.viewOnceMessage.message)
  if (msg?.viewOnceMessageV2?.message) return unwrapMessage(msg.viewOnceMessageV2.message)
  if (msg?.viewOnceMessageV2Extension?.message) return unwrapMessage(msg.viewOnceMessageV2Extension.message)
  if (msg?.documentWithCaptionMessage?.message) return unwrapMessage(msg.documentWithCaptionMessage.message)
  return msg
}

function extractMessage(data: any): {
  text: string
  mediaUrl?: string
  mediaType?: string
  mediaMimetype?: string
  mediaFilename?: string
  audioSeconds?: number
  audioPtt?: boolean
} | null {
  const msg = unwrapMessage(data?.message)
  if (!msg) return null

  if (msg.conversation) return { text: msg.conversation }
  if (msg.extendedTextMessage?.text) return { text: msg.extendedTextMessage.text }
  if (msg.imageMessage) return { text: msg.imageMessage.caption || '', mediaType: 'image', mediaUrl: msg.imageMessage.url, mediaMimetype: msg.imageMessage.mimetype }
  if (msg.videoMessage) return { text: msg.videoMessage.caption || '', mediaType: 'video', mediaUrl: msg.videoMessage.url, mediaMimetype: msg.videoMessage.mimetype }
  if (msg.audioMessage) return { text: '[Áudio]', mediaType: 'audio', mediaUrl: msg.audioMessage.url, mediaMimetype: msg.audioMessage.mimetype, audioSeconds: msg.audioMessage.seconds, audioPtt: msg.audioMessage.ptt }
  if (msg.documentMessage) return { text: msg.documentMessage.fileName || '[Documento]', mediaType: 'document', mediaUrl: msg.documentMessage.url, mediaMimetype: msg.documentMessage.mimetype, mediaFilename: msg.documentMessage.fileName }

  // Álbum (várias fotos/vídeos selecionados juntos no celular e enviados de uma vez):
  // confirmado em produção que a Evolution só entrega esse "anúncio" com a quantidade
  // esperada — nunca as mídias individuais como eventos separados. Sem tratar esse
  // caso, a mensagem inteira desaparecia sem nenhum rastro no CRM; agora pelo menos
  // fica visível que algo foi enviado, mesmo sem conseguir mostrar as fotos.
  if (msg.albumMessage) {
    const { expectedImageCount = 0, expectedVideoCount = 0 } = msg.albumMessage
    const parts: string[] = []
    if (expectedImageCount) parts.push(`${expectedImageCount} foto(s)`)
    if (expectedVideoCount) parts.push(`${expectedVideoCount} vídeo(s)`)
    return { text: `📷 Álbum com ${parts.join(' e ') || 'mídias'} enviado direto do WhatsApp — abra no celular pra ver.` }
  }

  return null
}

export type ProcessResult =
  | { status: 'created'; activityId: string }
  | { status: 'skipped'; reason: string }

/**
 * Processa uma única mensagem Evolution (`data` no formato key/message/
 * messageTimestamp/pushName/instanceId) pra uma organização — resolve o lead pelo
 * telefone, extrai conteúdo/mídia, deduplica por `evolution_message_id` e grava a
 * atividade. Idempotente: reprocessar a mesma mensagem (mesmo `key.id`) sempre cai no
 * skip 'duplicate', o que é o que permite a reconciliação periódica reprocessar uma
 * janela de mensagens sem se preocupar em filtrar o que já foi importado.
 */
export async function processEvolutionMessage(
  orgId: string,
  data: any,
  meta: { instance?: string | null; sender?: string | null } = {}
): Promise<ProcessResult> {
  const key = data?.key
  if (!key) return { status: 'skipped', reason: 'no key' }

  // fromMe = true também ocorre quando a mensagem é enviada direto pelo WhatsApp
  // (fora do CRM). Nesse caso registramos como atividade outbound em vez de ignorar.
  const isFromMe = !!key.fromMe

  // Extract phone from remoteJid (format: "5511999999999@s.whatsapp.net" or "@g.us" for groups).
  // Contatos endereçados no novo modo "lid" ("<id>@lid") não carregam o telefone em remoteJid;
  // o número real vem em remoteJidAlt ("5511999999999@s.whatsapp.net").
  const remoteJid: string = key.remoteJid || ''
  const isGroup = remoteJid.endsWith('@g.us')
  // Mensagens de grupo não viram lead/conversa no CRM: uma mensagem de grupo mistura
  // várias pessoas num único "contato", o que já causou risco de PII vazando entre
  // clientes distintos que estão no mesmo grupo. Ignorada o mais cedo possível, antes
  // de criar lead, gravar atividade ou disparar o webhook de saída.
  if (isGroup) return { status: 'skipped', reason: 'group' }
  const phoneJid = (!isGroup && key.addressingMode === 'lid' && key.remoteJidAlt) ? key.remoteJidAlt : remoteJid
  const phoneJid_ = phoneJid.split('@')[0]
  if (!phoneJid_) return { status: 'skipped', reason: 'no phone' }
  // Nono dígito: o JID pode vir sem o 9 do celular (ver telefoneVariantes em
  // leadSources). Grava a forma canônica e casa com as duas.
  const variantes = telefoneVariantes(phoneJid_)
  const phone = telefoneCanonico(phoneJid_) || phoneJid_

  const extracted = extractMessage(data)
  if (!extracted) {
    if (isFromMe) await logDiagnostic('no_extractable_content_fromme', orgId, { data, meta })
    return { status: 'skipped', reason: 'no message content' }
  }

  const senderName = data?.pushName || phone

  // Find the Evolution integration for this org
  const [integration] = await db
    .select({ id: integrations.id })
    .from(integrations)
    .where(
      and(
        eq(integrations.organizationId, orgId),
        eq(integrations.type, 'whatsapp_evolution'),
        isNull(integrations.deletedAt)
      )
    )
    .limit(1)

  // Find or create lead by phone
  let leadCriadoAgora = false
  let [lead] = await db
    .select({
      id: leads.id, title: leads.title, phone: leads.phone,
      // Quem falou por último antes desta mensagem — diz se a pessoa está
      // respondendo a automação (ver o publishEvent lá embaixo).
      ultimoRemetente: leads.lastMessageSenderType,
    })
    .from(leads)
    .where(
      and(
        eq(leads.organizationId, orgId),
        inArray(leads.phone, variantes),
        isNull(leads.deletedAt)
      )
    )
    .limit(1)

  if (!lead) {
    try {
      const [newLead] = await db
        .insert(leads)
        .values({
          organizationId: orgId,
          // Em fromMe, pushName é o nome do próprio dono do WhatsApp, não do contato.
          title: isFromMe ? phone : (senderName || phone),
          phone,
          isGroup,
          integrationId: integration?.id || null,
          // Conversa do WhatsApp não entra no funil — mesma regra da Z-API (ver
          // zapiInbound). O Kanban é dos leads de aquisição; quem atende promove
          // a conversa escolhendo a etapa, se for o caso.
          stageId: null,
          customAttributes: { origem: 'conversa_whatsapp' },
          lastActivityAt: new Date(),
        })
        .returning({
          id: leads.id, title: leads.title, phone: leads.phone,
          ultimoRemetente: leads.lastMessageSenderType,
        })

      lead = newLead
      leadCriadoAgora = true

      // Só busca a foto num lead recém-criado (primeira mensagem do contato) — não
      // faz sentido rebuscar a cada mensagem. fetchEvolutionProfilePicture já engole
      // qualquer erro e retorna null, então isso nunca derruba o processamento da
      // mensagem em si.
      // Grupo não: a foto viria pelo telefone de um participante (mesma
      // pegadinha que trocou a foto do grupo na Z-API).
      const avatarUrl = isGroup ? null : await fetchEvolutionProfilePicture(orgId, phone)
      if (avatarUrl) {
        await db.update(leads).set({ avatarUrl }).where(eq(leads.id, lead.id))
      }
    } catch (err) {
      // Duas mensagens quase simultâneas pro mesmo telefone corriam o mesmo SELECT
      // acima antes de qualquer INSERT commitar, e cada uma criava seu próprio lead —
      // já causou duplicata real em produção. A constraint leads_org_phone_unique
      // garante que só uma vence; a outra recupera o lead que já foi criado.
      if (!isUniqueViolation(err)) throw err
      const [existingLead] = await db
        .select({
          id: leads.id, title: leads.title, phone: leads.phone,
          ultimoRemetente: leads.lastMessageSenderType,
        })
        .from(leads)
        .where(and(eq(leads.organizationId, orgId), inArray(leads.phone, variantes), isNull(leads.deletedAt)))
        .limit(1)
      if (!existingLead) throw err
      lead = existingLead
    }
  }

  // Deduplicate by Evolution message ID
  const messageId = key.id
  if (messageId) {
    const existing = await db
      .select({ id: leadActivities.id })
      .from(leadActivities)
      .where(
        and(
          eq(leadActivities.organizationId, orgId),
          eq(leadActivities.leadId, lead.id)
        )
      )
      .limit(100)

    const duplicate = existing.find(
      (a: any) => (a as any).metadata?.evolution_message_id === messageId
    )
    if (duplicate) return { status: 'skipped', reason: 'duplicate' }
  }

  // A URL bruta do payload é um link criptografado (*.enc) do CDN do WhatsApp — não
  // abre direto no navegador e expira em poucos dias. Pedimos pra Evolution API
  // decriptar e re-hospedamos num link estável antes de salvar.
  let hostedMediaUrl: string | undefined
  let hostedMimetype: string | undefined
  if (extracted.mediaUrl && messageId) {
    const hosted = await downloadEvolutionMedia(orgId, { id: messageId, remoteJid, fromMe: isFromMe })
    if (hosted) {
      hostedMediaUrl = hosted.url
      hostedMimetype = hosted.mimetype || extracted.mediaMimetype
    }
  }

  const metadata: Record<string, any> = {
    source: 'evolution',
    direction: isFromMe ? 'outbound' : 'inbound',
    evolution_message_id: messageId,
  }
  if (isGroup) metadata.is_group = true
  if (!isFromMe) metadata.sender_name = senderName
  // Só grava media_url se conseguimos decriptar e re-hospedar — um link *.enc
  // quebrado no chat é pior do que só mostrar o rótulo de texto (ex: "🎵 Áudio").
  if (hostedMediaUrl) metadata.media_url = hostedMediaUrl
  if (extracted.mediaType) metadata.media_type = extracted.mediaType
  if (hostedMimetype || extracted.mediaMimetype) metadata.media_mimetype = hostedMimetype || extracted.mediaMimetype
  if (extracted.mediaFilename) metadata.media_filename = extracted.mediaFilename
  if (extracted.audioPtt !== undefined) metadata.audio_ptt = extracted.audioPtt

  // Mensagem reconciliada tarde (reconciliação periódica pegando algo que o webhook em
  // tempo real perdeu) preserva o horário real do envio — senão ela pula pro topo da
  // timeline como se tivesse acabado de chegar, fora de ordem cronológica.
  const messageTimestampMs = typeof data?.messageTimestamp === 'number' ? data.messageTimestamp * 1000 : undefined

  let activity: { id: string }
  try {
    ;[activity] = await db
      .insert(leadActivities)
      .values({
        organizationId: orgId,
        leadId: lead.id,
        type: 'whatsapp',
        content: extracted.text,
        metadata,
        ...(messageTimestampMs ? { createdAt: new Date(messageTimestampMs) } : {}),
      })
      .returning({ id: leadActivities.id })
  } catch (err) {
    // Rede de segurança pro dedupe fraco acima (só olha as últimas 100 activities DO
    // MESMO lead) — a constraint lead_activities_evolution_msgid_unique é global e já
    // pegou um caso real: a mesma mensagem batendo num lead-fantasma diferente do lead
    // certo, quando o webhook chegou duplicado e a resolução de telefone divergiu.
    if (!isUniqueViolation(err)) throw err
    return { status: 'skipped', reason: 'duplicate' }
  }

  // Update lead
  const leadUpdates: Record<string, any> = {
    lastMessageContent: extracted.text,
    lastMessageSenderType: isFromMe ? 'human' : 'lead',
    lastActivityAt: new Date(),
    lastActivityType: 'whatsapp',
    isUnread: !isFromMe,
    // Mensagem nova do cliente desarquiva a conversa sozinha (igual WhatsApp) — mensagem
    // que a própria empresa manda não deve tirar do arquivo.
    ...(!isFromMe ? { isArchived: false } : {}),
    integrationId: integration?.id || null,
  }
  if (!isFromMe) {
    leadUpdates.title = lead.title === lead.phone ? senderName : lead.title
  } else {
    const [stage] = await db
      .select({ id: pipelineStages.id })
      .from(pipelineStages)
      .where(
        and(
          eq(pipelineStages.organizationId, orgId),
          isNull(pipelineStages.deletedAt),
          ilike(pipelineStages.name, 'Em atendimento')
        )
      )
      .limit(1)
    if (stage) leadUpdates.stageId = stage.id
  }

  await db.update(leads).set(leadUpdates).where(eq(leads.id, lead.id))

  await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: activity.id })
  // Contato desconhecido que mandou mensagem é lead novo — e as telas abertas
  // (e o aviso sonoro) precisam saber disso, não só que "algo mudou".
  if (leadCriadoAgora) {
    await publishEvent(channels.orgLeads(orgId), events.LEAD_CREATED, { id: lead.id })
  }

  // Respondeu a automação? O último a falar era o sistema e agora é a pessoa.
  // Vale só pra mensagem que ENTRA — o eco da nossa própria mensagem não conta.
  if (!isFromMe && (lead as any).ultimoRemetente === 'automated') {
    await publishEvent(channels.orgLeads(orgId), events.LEAD_REPLIED_AUTOMATION, {
      id: lead.id,
      title: lead.title,
    })
    // Depois de responder o webhook: o aviso é uma chamada a mais pra Z-API e
    // não pode atrasar (nem derrubar) o registro da mensagem.
    const idDoLead = lead.id
    const textoResposta = extracted.text
    after(() => avisarGrupoRespostaAutomacao(orgId, idDoLead, textoResposta))
  }
  await publishEvent(channels.orgLeads(orgId), events.LEAD_UPDATED, { id: lead.id })

  if (!isFromMe) {
    after(() => notifyInboundMessage(orgId, lead.id, { text: extracted.text, mediaType: extracted.mediaType }))
  }

  const chatLid = (!isGroup && key.addressingMode === 'lid' && remoteJid.endsWith('@lid')) ? remoteJid : null
  const connectedPhone = typeof meta.sender === 'string' ? meta.sender.split('@')[0] : null
  const momment = messageTimestampMs ?? Date.now()

  await dispatchOutboundWebhook(orgId, {
    leadId: lead.id,
    phone,
    fromMe: isFromMe,
    isGroup,
    chatLid,
    senderName: isFromMe ? null : senderName,
    chatName: lead.title,
    content: extracted.text,
    messageId,
    timestamp: momment,
    instanceId: meta.instance || integration?.id || null,
    connectedPhone,
    mediaType: extracted.mediaType as any,
    mediaUrl: hostedMediaUrl,
    mediaMimetype: hostedMimetype || extracted.mediaMimetype,
    mediaFilename: extracted.mediaFilename,
    audioSeconds: extracted.audioSeconds,
    audioPtt: extracted.audioPtt,
  })

  return { status: 'created', activityId: activity.id }
}
