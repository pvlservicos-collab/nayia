/**
 * POST/GET /api/webhooks/facebook
 * Webhook para receber mensagens da API Oficial do Facebook/WhatsApp Cloud
 *
 * GET  → Verificação do webhook pelo Facebook (hub.challenge)
 * POST → Receber mensagens inbound
 *
 * Configure no Facebook Developers:
 *   URL: https://seu-app.vercel.app/api/webhooks/facebook?org_id=SEU_ORG_ID
 *   Verify Token: valor de FACEBOOK_WEBHOOK_VERIFY_TOKEN
 */
import { guardarDoEndereco } from '@/lib/armazem'
import { getWhatsAppCredentials } from '@/lib/whatsapp'
import { NextRequest, after } from 'next/server'
import { db } from '@/lib/db'
import { leads, leadActivities, pipelineStages, integrationMessageLogs, integrations } from '@/lib/schema'
import { eq, and, isNull, ilike, asc, sql } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { dispatchOutboundWebhook } from '@/lib/outbound-webhook'
import { ORGANIZATION_ID } from '@/lib/automated-message'
import { isUniqueViolation } from '@/lib/db-helpers'
import { notifyInboundMessage } from '@/lib/push'
import { transcreverAtividade } from '@/lib/transcricao'
import { acharLeadDaLinha, integracaoDoTipo } from '@/lib/leadDaLinha'
import { telefoneCanonico, telefoneVariantes } from '@/lib/leadSources'
import { etapaInicialDaLinha } from '@/lib/etapaDaLinha'

/** O que a conversa mostra quando a Meta entrega a mensagem sem conteúdo. */
const AVISO_SEM_CONTEUDO_DA_META =
  '⚠️ A pessoa mandou algo que a API oficial não mostra (foto de visualização única, enquete ou recurso novo do WhatsApp). Peça para reenviar.'

/**
 * Manda para o fluxo da captação (n8n) o que chegou no número oficial.
 * Sem CAPTACAO_OFICIAL_WEBHOOK_URL no .env, não faz nada. Falhar aqui nunca
 * derruba o registro da mensagem, que já aconteceu.
 */
async function repassarParaCaptacao(corpo: Record<string, unknown>) {
  const url = process.env.CAPTACAO_OFICIAL_WEBHOOK_URL
  if (!url) return
  const controle = new AbortController()
  const prazo = setTimeout(() => controle.abort(), 8000)
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-captacao-segredo': process.env.CAPTACAO_OFICIAL_SEGREDO || '',
      },
      body: JSON.stringify(corpo),
      signal: controle.signal,
    })
    if (!r.ok) console.error('[Facebook Webhook] a captação respondeu', r.status)
  } catch (err) {
    console.error('[Facebook Webhook] repasse para a captação falhou', err)
  } finally {
    clearTimeout(prazo)
  }
}

/** A Meta avisou que não sabe entregar este tipo (`unsupported`, erro 131051). */
function ehMensagemSemConteudoDaMeta(message: any): boolean {
  return message?.type === 'unsupported'
    || (Array.isArray(message?.errors) && message.errors.some((e: any) => Number(e?.code) === 131051))
}

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const mode = searchParams.get('hub.mode')
  const token = searchParams.get('hub.verify_token')
  const challenge = searchParams.get('hub.challenge')

  if (mode === 'subscribe' && token === process.env.FACEBOOK_WEBHOOK_VERIFY_TOKEN) {
    return new Response(challenge, { status: 200 })
  }
  return new Response('Forbidden', { status: 403 })
}

/**
 * Baixa uma mídia do WhatsApp Cloud API e guarda no armazém do CRM.
 * Retorna o endereço (relativo) e o mimetype, ou null se não foi possível.
 *
 * A MÍDIA DO NÚMERO OFICIAL SE PERDIA INTEIRA (29/09/2026). Esta função só
 * lia o token de `integration_secrets`, e ele nunca esteve lá (mora no .env,
 * META_TOKEN -- ver `getWhatsAppCredentials`); e, se lesse, o Blob da Vercel
 * não existe neste servidor. Resultado medido: nenhuma foto, áudio ou
 * documento recebido pelo 8456-0874 ficou no CRM, só o rótulo "🎵 Áudio".
 */
async function downloadWhatsappMedia(orgId: string, mediaId: string): Promise<{ url: string; mimetype?: string } | null> {
  let apiVersion: string
  let token: string
  try {
    ({ apiVersion, token } = await getWhatsAppCredentials(orgId))
  } catch {
    return null
  }

  const metaRes = await fetch(`https://graph.facebook.com/${apiVersion}/${mediaId}`, {
    headers: { Authorization: `Bearer ${token}` },
  })
  if (!metaRes.ok) return null
  const meta = await metaRes.json()
  if (!meta?.url) return null

  const guardada = await guardarDoEndereco(`whatsapp-media/${orgId}`, mediaId, meta.url,
                                          { Authorization: `Bearer ${token}` })
  if (!guardada) return null
  return { url: guardada.url, mimetype: meta.mime_type || guardada.mimetype }
}

const MEDIA_TYPES = ['image', 'video', 'audio', 'document', 'sticker'] as const
const MEDIA_LABELS: Record<string, string> = {
  image: '📷 Imagem',
  video: '🎥 Vídeo',
  audio: '🎵 Áudio',
  document: '📄 Documento',
  sticker: '✨ Figurinha',
}

// ── Instagram Direct ────────────────────────────────────────────────────────
// entry.id em eventos de Instagram Messaging é o ID do objeto assinado no
// webhook (IG Business Account ou a Page conectada, dependendo de como a
// assinatura foi configurada) — testamos os dois campos salvos na integração.
async function findInstagramIntegration(entryId: string) {
  const [integration] = await db.select({ id: integrations.id, organizationId: integrations.organizationId })
    .from(integrations)
    .where(and(
      eq(integrations.type, 'instagram_direct'),
      isNull(integrations.deletedAt),
      sql`(${integrations.config}->>'instagram_business_account_id' = ${entryId} OR ${integrations.config}->>'connected_page_id' = ${entryId})`
    ))
    .limit(1)
  return integration
}

async function downloadInstagramMedia(orgId: string, url: string, mediaType: string): Promise<string | null> {
  const guardada = await guardarDoEndereco(`instagram-media/${orgId}`, `${mediaType}-${Date.now()}`, url)
  return guardada?.url ?? null
}

// share/ig_reel/story_mention: conteúdo compartilhado de dentro do Instagram
// (Reels, posts, menção em story). A Meta não inclui uma URL baixável pra esses
// tipos no payload do webhook — só um id de referência (ex: reel_video_id) que a
// Graph API não expõe pra download. Por isso não tem mídia re-hospedada pra eles,
// só o rótulo — não é um bug do parsing, é limitação da própria API da Meta.
const IG_MEDIA_LABELS: Record<string, string> = {
  image: '📷 Imagem',
  video: '🎥 Vídeo',
  audio: '🎵 Áudio',
  file: '📄 Documento',
  share: '🔗 Publicação compartilhada (sem prévia — Meta não envia o link)',
  ig_reel: '🎬 Reels compartilhado (sem prévia — Meta não envia o vídeo original)',
  story_mention: '📸 Menção em story (sem prévia — Meta não envia a imagem)',
}

/**
 * Instagram Messaging entrega eventos no formato `entry.messaging[]` (padrão
 * Messenger Platform) — diferente do `entry.changes[].value.messages[]` do
 * WhatsApp Cloud API. Validado contra payloads reais em 2026-07-08 (texto e
 * anexo tipo ig_reel) — os dois formatos batem com o parsing abaixo.
 */
async function handleInstagramEntry(entry: any) {
  const integration = await findInstagramIntegration(entry.id)
  if (!integration) return Response.json({ status: 'ignored: instagram integration not found' })

  const orgId = integration.organizationId

  for (const evt of entry.messaging || []) {
    const message = evt.message
    if (!message) continue

    // Mensagens ecoadas (enviadas pela própria Page — seja pela nossa API, seja
    // manualmente pelo app do Instagram) são ignoradas aqui: o envio pela nossa
    // API já grava a activity no momento do envio, então tratar o echo duplicaria
    // a mensagem. Consequência: mensagem enviada manualmente fora do CRM não
    // sincroniza automaticamente nesta v1.
    if (message.is_echo) continue

    const senderId = evt.sender?.id
    if (!senderId) continue

    let content = message.text || ''
    let mediaUrl: string | undefined
    let mediaType: string | undefined

    const attachment = message.attachments?.[0]
    if (attachment?.type) {
      mediaType = attachment.type === 'file' ? 'document' : attachment.type
      const rawUrl = attachment.payload?.url
      if (rawUrl) {
        const hosted = await downloadInstagramMedia(orgId, rawUrl, mediaType || 'file')
        if (hosted) mediaUrl = hosted
      }
      if (!content) content = IG_MEDIA_LABELS[attachment.type] || '[Mídia recebida]'
    } else if (!content) {
      content = '[Mensagem recebida]'
    }

    // Instagram não tem telefone — lead é resolvido por external_id (IGSID) +
    // integração, não por phone como no WhatsApp.
    const [existing] = await db.select({ id: leads.id }).from(leads)
      .where(and(
        eq(leads.organizationId, orgId),
        eq(leads.integrationId, integration.id),
        eq(leads.externalId, senderId),
        isNull(leads.deletedAt)
      ))
      .limit(1)

    let leadId = existing?.id
    if (!leadId) {
      const [firstStage] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, orgId), isNull(pipelineStages.deletedAt)))
        .orderBy(asc(pipelineStages.rank)).limit(1)

      const { getInstagramUserProfile } = await import('@/lib/instagram')
      const profile = await getInstagramUserProfile(orgId, integration.id, senderId)

      try {
        const [newLead] = await db.insert(leads).values({
          organizationId: orgId,
          integrationId: integration.id,
          title: profile?.name || senderId,
          externalId: senderId,
          avatarUrl: profile?.profilePic || null,
          customAttributes: profile?.username ? { instagram_username: profile.username } : {},
          stageId: firstStage?.id || null,
          lastActivityAt: new Date(),
        }).returning({ id: leads.id })
        leadId = newLead.id
      } catch (err) {
        // Mesma race condition do WhatsApp: duas mensagens quase simultâneas do mesmo
        // IGSID, cada uma criava seu próprio lead sem constraint. Agora
        // leads_integration_external_id_unique garante que só uma vence.
        if (!isUniqueViolation(err)) throw err
        const [raceLead] = await db.select({ id: leads.id }).from(leads)
          .where(and(eq(leads.organizationId, orgId), eq(leads.integrationId, integration.id), eq(leads.externalId, senderId), isNull(leads.deletedAt)))
          .limit(1)
        if (!raceLead) throw err
        leadId = raceLead.id
      }
    }

    let activity: { id: string }
    try {
      ;[activity] = await db.insert(leadActivities).values({
        organizationId: orgId,
        leadId,
        type: 'whatsapp',
        content,
        metadata: {
          direction: 'inbound',
          source: 'instagram',
          channel: 'instagram_direct',
          instagram_message_id: message.mid,
          ...(mediaUrl ? { media_url: mediaUrl, media_type: mediaType } : {}),
        },
      }).returning({ id: leadActivities.id })
    } catch (err) {
      if (!isUniqueViolation(err)) throw err
      return Response.json({ status: 'ignored: duplicate message' })
    }

    await db.update(leads).set({
      lastMessageContent: content,
      lastMessageSenderType: 'lead',
      lastActivityAt: new Date(),
      isUnread: true,
      isArchived: false,
    }).where(eq(leads.id, leadId))

    await publishEvent(channels.leadActivities(leadId), events.ACTIVITY_CREATED, { id: activity.id })
    await publishEvent(channels.orgLeads(orgId), events.LEAD_UPDATED, { id: leadId })

    after(() => notifyInboundMessage(orgId, leadId, { text: content, mediaType }))

    await db.insert(integrationMessageLogs).values({
      organizationId: orgId,
      source: 'instagram',
      direction: 'inbound',
      content,
      leadId,
      status: 'success',
      payload: evt,
    })
  }

  return Response.json({ status: 'ok' })
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json()

    const entry = body.entry?.[0]

    // Instagram Messaging usa `entry.messaging[]`, ausente nos payloads do
    // WhatsApp Cloud API — discrimina os dois formatos antes de seguir.
    if (entry?.messaging?.length) {
      return await handleInstagramEntry(entry)
    }

    const changes = entry?.changes?.[0]
    const value = changes?.value
    const message = value?.messages?.[0]

    if (!message) return Response.json({ status: 'ignored: no message' })

    // Resolve org_id: URL param (legado) ou via WABA ID no payload
    let orgId = new URL(req.url).searchParams.get('org_id')
    if (!orgId) {
      const wabaId = entry?.id as string | undefined
      if (wabaId) {
        const { integrations } = await import('@/lib/schema')
        const { sql } = await import('drizzle-orm')
        const [found] = await db.select({ organizationId: integrations.organizationId })
          .from(integrations)
          .where(sql`${integrations.config}->>'waba_id' = ${wabaId}`)
          .limit(1)
        orgId = found?.organizationId ?? null
      }
    }

    if (!orgId) return Response.json({ status: 'ignored: org not found' })

    // Detecta "echo" de mensagem enviada pelo próprio número (ex: enviada via app oficial do WhatsApp)
    const ownNumber = (value?.metadata?.display_phone_number || '').replace(/\D/g, '')
    const fromNumber = (message.from || '').replace(/\D/g, '')
    const isOutboundEcho = !!ownNumber && ownNumber === fromNumber

    const phone = isOutboundEcho ? (value?.contacts?.[0]?.wa_id || message.from) : message.from
    const senderName = value?.contacts?.[0]?.profile?.name || phone

    // Mídia (imagem, áudio, vídeo, documento, figurinha)
    let mediaUrl: string | undefined
    let mediaType: string | undefined
    let mediaMimetype: string | undefined
    let mediaFilename: string | undefined
    let mediaIdMeta: string | undefined
    let content = message.text?.body || ''

    if ((MEDIA_TYPES as readonly string[]).includes(message.type)) {
      mediaType = message.type
      const mediaObj = message[message.type]
      mediaMimetype = mediaObj?.mime_type
      mediaFilename = mediaObj?.filename
      if (mediaObj?.caption) content = mediaObj.caption

      if (mediaObj?.id) {
        mediaIdMeta = String(mediaObj.id)
        try {
          const downloaded = await downloadWhatsappMedia(orgId, mediaObj.id)
          if (downloaded) {
            mediaUrl = downloaded.url
            mediaMimetype = downloaded.mimetype || mediaMimetype
          }
        } catch (err) {
          console.error('[Facebook Webhook] media download failed', err)
        }
      }

      if (!content) content = MEDIA_LABELS[message.type] || '[Mídia recebida]'
    } else if (message.type === 'button') {
      content = message.button?.text || message.button?.payload || '[Botão pressionado]'
    } else if (message.type === 'interactive') {
      content =
        message.interactive?.button_reply?.title ||
        message.interactive?.list_reply?.title ||
        '[Resposta interativa]'
    } else if (message.type === 'reaction') {
      content = `Reagiu: ${message.reaction?.emoji || '👍'}`
    } else if (message.type === 'location') {
      const loc = message.location
      content = `📍 Localização: ${loc?.name || `${loc?.latitude}, ${loc?.longitude}`}`
    } else if (ehMensagemSemConteudoDaMeta(message)) {
      // A META MANDA VAZIO (28/09/2026). `type: "unsupported"`, erro 131051
      // "Message type unknown": a pessoa mandou algo que a API oficial não
      // entrega -- foto de visualização única, enquete, recurso novo do app. O
      // texto não chega para ninguém; o que dá para fazer é pedir de novo.
      // Antes aparecia "[Mensagem recebida]", que não explicava nada (Pedro:
      // "vê se isso aqui é bug").
      content = AVISO_SEM_CONTEUDO_DA_META
    } else if (!content) {
      content = '[Mensagem recebida]'
    }

    /* O LEAD DA LINHA OFICIAL (Tel, 28/09/2026: "API oficial com as coisas que
       recebemos só da API oficial... não misturando contatos").

       Antes o lead era procurado por qualquer pedaço do telefone, em qualquer
       linha, e nascia SEM integração -- a conversa de quem escrevia para o
       8456-0874 não aparecia em aba nenhuma (5511999910621, 28/09). Agora é
       (telefone, linha oficial), como na Z-API (ver `leadDaLinha.ts`). */
    const linhaOficial = await integracaoDoTipo(orgId, 'whatsapp_cloud_official')
    const telefones = telefoneVariantes(phone)
    const existing = await acharLeadDaLinha(orgId, telefones.length ? telefones : [phone], linhaOficial)

    let leadId = existing?.id
    if (!leadId) {
      // A etapa do pipeline DA LINHA, não a primeira da organização -- os
      // pipelines têm etapa de rank 1 cada um, e o banco devolvia qualquer uma.
      const etapa = await etapaInicialDaLinha(orgId, 'whatsapp_cloud_official')

      try {
        const [newLead] = await db.insert(leads).values({
          organizationId: orgId,
          title: senderName,
          phone: telefoneCanonico(phone) || phone,
          integrationId: linhaOficial,
          stageId: etapa,
          lastActivityAt: new Date(),
        }).returning({ id: leads.id })
        leadId = newLead.id
      } catch (err) {
        // Mesma race condition já vista no Evolution: duas mensagens quase simultâneas
        // pro mesmo telefone, cada uma cria seu próprio lead sem constraint. Agora a
        // constraint leads_org_phone_unique (telefone + linha) garante que só uma vence.
        if (!isUniqueViolation(err)) throw err
        const raceLead = await acharLeadDaLinha(orgId, telefones.length ? telefones : [phone], linhaOficial)
        if (!raceLead) throw err
        leadId = raceLead.id
      }
    }

    let activity: { id: string }
    try {
      ;[activity] = await db.insert(leadActivities).values({
        organizationId: orgId,
        leadId,
        type: 'whatsapp',
        content,
        metadata: {
          direction: isOutboundEcho ? 'outbound' : 'inbound',
          source: isOutboundEcho ? 'whatsapp_app' : 'facebook_cloud',
          // por qual número passou (a Z-API já grava o dela)
          channel: 'whatsapp_cloud_official',
          sender_name: senderName,
          // o erro da Meta, quando ela mandou a mensagem sem conteúdo
          ...(ehMensagemSemConteudoDaMeta(message)
            ? { meta_sem_conteudo: true, meta_erro: message.errors?.[0] ?? { type: message.type } }
            : {}),
          ...(message.id ? { whatsapp_message_id: message.id } : {}),
          ...(mediaUrl ? { media_url: mediaUrl, media_type: mediaType, media_mimetype: mediaMimetype, ...(mediaFilename ? { media_filename: mediaFilename } : {}) } : {}),
          ...(mediaIdMeta ? { whatsapp_media_id: mediaIdMeta } : {}),
        },
      }).returning({ id: leadActivities.id })
    } catch (err) {
      // Replay do webhook da Meta (oficialmente pode reenviar o mesmo evento) — antes
      // duplicava incondicionalmente, sem checagem nenhuma. A constraint
      // lead_activities_whatsapp_msgid_unique agora rejeita a segunda tentativa.
      if (!isUniqueViolation(err)) throw err
      return Response.json({ ok: true, skipped: 'duplicate' })
    }

    await db.update(leads).set({
      lastMessageContent: content,
      lastMessageSenderType: isOutboundEcho ? 'agent' : 'lead',
      lastActivityAt: new Date(),
      isUnread: !isOutboundEcho,
      // Mensagem nova do cliente desarquiva sozinha (igual WhatsApp) — eco de mensagem
      // que a própria empresa mandou não deve tirar do arquivo.
      ...(!isOutboundEcho ? { isArchived: false } : {}),
    }).where(eq(leads.id, leadId))

    await publishEvent(channels.leadActivities(leadId), events.ACTIVITY_CREATED, { id: activity.id })
    await publishEvent(channels.orgLeads(orgId), events.LEAD_UPDATED, { id: leadId })

    if (!isOutboundEcho) {
      after(() => notifyInboundMessage(orgId, leadId, { text: content, mediaType }))
    }
    // a transcrição embaixo do áudio, também na linha oficial (29/09)
    if (mediaType === 'audio' && mediaUrl) {
      const idDoAudio = activity.id
      after(() => transcreverAtividade(idDoAudio).then(() => undefined)
        .catch((e) => console.error('[transcricao]', idDoAudio, e?.message || e)))
    }

    /* A NAY DE CAPTAÇÃO CONVERSA PELO NÚMERO OFICIAL (Pedro, 28/09/2026). O que
       uma pessoa manda para cá vai também para o fluxo da captação, no formato
       da Z-API, marcado `canal: 'oficial'`; lá ele decide se é dono em captação
       e se pode responder, e a resposta volta por /api/webhooks/captacao-oficial.
       Não vai: o nosso eco e a mensagem que a Meta entregou sem conteúdo. Depois
       de responder o webhook -- a captação não pode atrasar a Meta. */
    if (!isOutboundEcho && !ehMensagemSemConteudoDaMeta(message)) {
      const temTexto = !!(message.text?.body || (mediaType && content && content !== MEDIA_LABELS[message.type]))
      const corpoCaptacao: Record<string, unknown> = {
        type: 'ReceivedCallback',
        canal: 'oficial',
        phone: fromNumber,
        fromMe: false,
        fromApi: false,
        isGroup: false,
        senderName,
        messageId: message.id || null,
        momment: message.timestamp ? Number(message.timestamp) * 1000 : Date.now(),
        ...(temTexto && !mediaType ? { text: { message: content } } : {}),
        ...(mediaType === 'audio' && mediaUrl ? { audio: { audioUrl: mediaUrl, mimeType: mediaMimetype } } : {}),
        ...(mediaType === 'image' ? { image: { imageUrl: mediaUrl || '', caption: temTexto ? content : '' } } : {}),
        ...(mediaType === 'video' ? { video: { videoUrl: mediaUrl || '', caption: temTexto ? content : '' } } : {}),
        ...(mediaType === 'document' ? { document: { documentUrl: mediaUrl || '', caption: temTexto ? content : '' } } : {}),
        ...(mediaType === 'sticker' ? { sticker: { stickerUrl: mediaUrl || '' } } : {}),
        ...(message.type === 'reaction' ? { reaction: { value: message.reaction?.emoji || '' } } : {}),
        // botão de template / resposta interativa chegam como texto
        ...(!mediaType && !temTexto && message.type !== 'reaction' && content ? { text: { message: content } } : {}),
      }
      after(() => repassarParaCaptacao(corpoCaptacao))
    }

    await db.insert(integrationMessageLogs).values({
      organizationId: orgId,
      source: isOutboundEcho ? 'whatsapp_app' : 'facebook_cloud',
      direction: isOutboundEcho ? 'outbound' : 'inbound',
      phone,
      content,
      leadId,
      status: 'success',
      payload: body,
    })

    const momment = message.timestamp ? Number(message.timestamp) * 1000 : Date.now()

    await dispatchOutboundWebhook(orgId, {
      leadId,
      phone,
      fromMe: isOutboundEcho,
      isGroup: false,
      senderName: isOutboundEcho ? null : senderName,
      content,
      messageId: message.id || null,
      timestamp: momment,
      instanceId: value?.metadata?.phone_number_id || entry?.id || null,
      connectedPhone: ownNumber || null,
      mediaType: mediaType as any,
      mediaUrl,
      mediaMimetype,
      mediaFilename,
      audioPtt: message.type === 'audio' ? !!message.audio?.voice : undefined,
    })

    return Response.json({ status: 'ok' })
  } catch (err: any) {
    console.error('[Facebook Webhook]', err)
    return Response.json({ status: 'error', message: err.message }, { status: 500 })
  }
}
