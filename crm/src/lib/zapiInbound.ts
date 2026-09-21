import { after } from 'next/server'
import { db } from '@/lib/db'
import { leads, leadActivities, integrations, pipelineStages, webhookLogs } from '@/lib/schema'
import { eq, and, isNull, asc, ilike, inArray } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { dispatchOutboundWebhook } from '@/lib/outbound-webhook'
import { isUniqueViolation } from '@/lib/db-helpers'
import { notifyInboundMessage } from '@/lib/push'
import { avisarGrupoRespostaAutomacao } from '@/lib/avisoGrupo'
import { ZAPI_INTEGRATION_TYPE, rehospedarMidiaZapi, rehospedarFotoPerfil } from '@/lib/zapi'
import { telefoneVariantes, telefoneCanonico } from '@/lib/leadSources'

/**
 * Entrada de mensagens da Z-API.
 *
 * Espelha o que `evolutionInbound.ts` faz — resolve o lead pelo telefone, extrai
 * conteúdo e mídia, deduplica e grava a atividade — porque o resultado no CRM
 * precisa ser idêntico venha de onde vier: mesma timeline, mesmos campos, mesmo
 * comportamento de não-lido e de etapa. O que muda é só o formato do payload.
 *
 * O payload da Z-API é bem mais simples que o da Evolution/Baileys: em vez de
 * `message.imageMessage.url` embrulhado em containers de efêmera/ver-uma-vez,
 * vem um objeto por tipo (`image.imageUrl`, `audio.audioUrl`…) já resolvido, e a
 * URL é pública. Em compensação ela expira em 30 dias, daí o re-hospedar.
 */

export type ZapiProcessResult =
  | { status: 'created'; activityId: string }
  | { status: 'skipped'; reason: string }

export async function logZapiDiagnostico(reason: string, orgId: string, body: any) {
  try {
    await db.insert(webhookLogs).values({ payload: { origem: 'zapi', reason, org_id: orgId, body } })
  } catch (err) {
    console.error('[zapi webhook] diagnóstico não gravado', err)
  }
}

interface Extraido {
  text: string
  mediaUrl?: string
  mediaType?: string
  mediaMimetype?: string
  mediaFilename?: string
  audioSeconds?: number
}

/**
 * Conteúdo da mensagem, seja qual for o tipo.
 *
 * Cobre também os tipos que não têm mídia pra mostrar (contato, localização,
 * enquete): em vez de descartar — que foi o erro que já custou mensagens
 * invisíveis na Evolution — grava um texto dizendo o que chegou. Uma linha
 * "📍 Localização" na conversa é infinitamente melhor que um silêncio que
 * ninguém consegue explicar depois.
 */
function extrair(body: any): Extraido | null {
  if (body?.text?.message) return { text: String(body.text.message) }

  if (body?.image) {
    return {
      text: body.image.caption || '',
      mediaType: 'image',
      mediaUrl: body.image.imageUrl,
      mediaMimetype: body.image.mimeType,
    }
  }
  if (body?.video) {
    return {
      text: body.video.caption || '',
      mediaType: 'video',
      mediaUrl: body.video.videoUrl,
      mediaMimetype: body.video.mimeType,
    }
  }
  if (body?.audio) {
    return {
      text: '[Áudio]',
      mediaType: 'audio',
      mediaUrl: body.audio.audioUrl,
      mediaMimetype: body.audio.mimeType,
      audioSeconds: body.audio.seconds,
    }
  }
  if (body?.document) {
    return {
      text: body.document.fileName || '[Documento]',
      mediaType: 'document',
      mediaUrl: body.document.documentUrl,
      mediaMimetype: body.document.mimeType,
      mediaFilename: body.document.fileName,
    }
  }
  if (body?.sticker) {
    return { text: '[Figurinha]', mediaType: 'image', mediaUrl: body.sticker.stickerUrl }
  }

  if (body?.contact) {
    const nome = body.contact.displayName || body.contact.vCard?.split('FN:')[1]?.split('\n')[0] || 'contato'
    return { text: `👤 Contato compartilhado: ${nome}` }
  }
  if (body?.location) {
    const { latitude, longitude, address } = body.location
    return { text: `📍 Localização: ${address || `${latitude}, ${longitude}`}` }
  }
  if (body?.poll?.question) return { text: `📊 Enquete: ${body.poll.question}` }
  if (body?.reaction?.value) return { text: `Reagiu com ${body.reaction.value}` }
  if (body?.buttonsResponseMessage?.message) return { text: String(body.buttonsResponseMessage.message) }
  if (body?.listResponseMessage?.title) return { text: String(body.listResponseMessage.title) }

  return null
}

/**
 * Processa uma mensagem recebida da Z-API.
 *
 * Idempotente: reprocessar o mesmo `messageId` cai em 'duplicate'. A Z-API
 * reenvia o webhook quando a nossa resposta demora ou falha, então isso não é
 * teoria — sem o dedupe a mesma mensagem apareceria duas vezes na conversa.
 */
export async function processZapiMessage(orgId: string, body: any): Promise<ZapiProcessResult> {
  const messageId: string | undefined = body?.messageId
  const phoneBruto: string = String(body?.phone || '')
  const ehGrupo = !!body?.isGroup

  /*
   * Grupo é conversa, nunca lead.
   *
   * O identificador do grupo ("1203...-group") entra no lugar do telefone: é o
   * que a Z-API manda em `phone` e é o mesmo valor que ela aceita pra responder.
   * Não passa por telefoneVariantes — não é celular e inventar variante dele
   * daria um destinatário que não existe.
   *
   * A conversa de grupo nasce e continua FORA do funil (sem etapa, ver mais
   * abaixo): num grupo escrevem várias pessoas, e tratar isso como "um lead"
   * misturaria gente diferente num card só. O autor de cada mensagem fica em
   * `sender_name`/`participant_phone`, que é o que permite ler a conversa
   * sabendo quem falou.
   */
  const variantes = ehGrupo ? [phoneBruto] : telefoneVariantes(phoneBruto)
  const phone = ehGrupo
    ? phoneBruto
    : (telefoneCanonico(phoneBruto) || phoneBruto.replace(/\D/g, ''))
  if (!phone) return { status: 'skipped', reason: 'sem telefone' }

  /*
   * Comunidade, canal e lista de transmissão não são conversa com ninguém.
   *
   * Chegam com um id numérico gigante no lugar do telefone e `isGroup: false`,
   * então passavam como se fossem contato: viravam uma linha no chat chamada
   * "120363404701403742" (o "Pack de Figurinhas") que não dá pra abrir nem
   * responder. E como o id é recriado a cada mensagem nova, apagar a linha não
   * resolvia — ela voltava sozinha na próxima figurinha postada.
   *
   * Telefone com DDI cabe em 15 dígitos (padrão E.164); acima disso não é
   * telefone.
   */
  if (!ehGrupo && phone.replace(/\D/g, '').length > 14) {
    return { status: 'skipped', reason: 'comunidade/lista de transmissão' }
  }

  // Status de mensagem ("entregue", "lida") não é conteúdo — vem por outro
  // callback e nunca deve virar linha na timeline.
  if (body?.type && body.type !== 'ReceivedCallback') {
    return { status: 'skipped', reason: `callback ${body.type}` }
  }

  /*
   * Notificação de sistema não é mensagem de ninguém: alguém apagou uma
   * mensagem (REVOKE), trocou a descrição do grupo (GROUP_CHANGE_DESCRIPTION),
   * entrou ou saiu do grupo, a chamada caiu. Chegam como ReceivedCallback,
   * iguais a uma mensagem, mas sem conteúdo — e caíam no diagnóstico como
   * "conteúdo não extraído", enchendo o log de falso alarme. É o tipo de ruído
   * que faz alguém achar que a integração está com erro quando não está.
   */
  if (body?.notification) {
    return { status: 'skipped', reason: `notificação ${body.notification}` }
  }

  // Grupo que ninguém importou: descarta ANTES de tentar ler o conteúdo, pelo
  // mesmo motivo acima — não tem por que diagnosticar mensagem que ia pro lixo.
  if (ehGrupo) {
    const [grupoExiste] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(and(eq(leads.organizationId, orgId), eq(leads.phone, phone), isNull(leads.deletedAt)))
      .limit(1)
    if (!grupoExiste) return { status: 'skipped', reason: 'grupo não importado' }
  }

  const isFromMe = !!body?.fromMe
  const extraido = extrair(body)
  if (!extraido) {
    // Formato ainda não mapeado: registra o payload pra dar pra descobrir o que
    // era, em vez de a mensagem sumir sem rastro.
    await logZapiDiagnostico('conteudo_nao_extraido', orgId, body)
    return { status: 'skipped', reason: 'sem conteúdo reconhecido' }
  }

  const senderName: string = body?.senderName || body?.chatName || phone

  const [integration] = await db
    .select({ id: integrations.id })
    .from(integrations)
    .where(and(
      eq(integrations.organizationId, orgId),
      eq(integrations.type, ZAPI_INTEGRATION_TYPE),
      isNull(integrations.deletedAt)
    ))
    .limit(1)

  let leadCriadoAgora = false
  let [lead] = await db
    .select({
      id: leads.id, title: leads.title, phone: leads.phone, stageId: leads.stageId,
      // Quem falou por último ANTES desta mensagem: é o que diz se a pessoa
      // está respondendo a automação.
      ultimoRemetente: leads.lastMessageSenderType,
      avatarUrl: leads.avatarUrl,
    })
    .from(leads)
    .where(and(eq(leads.organizationId, orgId), inArray(leads.phone, variantes), isNull(leads.deletedAt)))
    .limit(1)

  /*
   * Grupo só existe no CRM se ALGUÉM o trouxe de propósito (pela importação).
   *
   * O número está em ~46 grupos e quase todos são conversa interna — equipe,
   * turmas de mentoria, churrasco. Se a chegada de mensagem criasse a conversa,
   * bastava alguém falar em qualquer um deles pra ele aparecer no chat, e a
   * lista voltaria a encher sozinha. Então: mensagem de grupo desconhecido é
   * descartada; a de grupo conhecido entra normalmente.
   */
  if (!lead && ehGrupo) {
    return { status: 'skipped', reason: 'grupo não importado' }
  }

  if (!lead) {
    try {
      const [novo] = await db
        .insert(leads)
        .values({
          organizationId: orgId,
          // Grupo se chama pelo nome do grupo. Em fromMe o senderName é o dono do
          // WhatsApp, não o contato — aí o telefone é o único nome honesto.
          title: ehGrupo
            ? (body?.chatName || phone)
            : (isFromMe ? phone : (senderName || phone)),
          // Mesma marca da importação: é conversa, não aquisição. Sem ela, o
          // relatório diário contaria cada contato do WhatsApp como "lead novo".
          customAttributes: { origem: 'conversa_whatsapp' },
          phone,
          isGroup: ehGrupo,
          integrationId: integration?.id || null,
          /*
           * Conversa que chega pelo WhatsApp NÃO entra no funil. Nunca.
           *
           * O Kanban é dos leads de aquisição — Agenda, site, indicação —, e
           * eles são o trabalho do time. Quem manda mensagem pro número pode ser
           * qualquer um: fornecedor, aluno antigo, o pessoal do escritório, e já
           * aconteceu de uma COMUNIDADE de figurinhas virar card em "Em aguardo"
           * no meio dos leads de verdade.
           *
           * Vira conversa no Chat, e ponto. Se quem atende reconhecer um negócio
           * ali, escolhe a etapa no painel do lead — aí entra no funil por
           * decisão de gente, que é como um lead deve nascer.
           */
          stageId: null,
          lastActivityAt: new Date(),
        })
        .returning({
          id: leads.id, title: leads.title, phone: leads.phone, stageId: leads.stageId,
          ultimoRemetente: leads.lastMessageSenderType, avatarUrl: leads.avatarUrl,
        })
      lead = novo
      leadCriadoAgora = true

      // A foto é tratada logo abaixo, num lugar só — e com as travas de grupo e
      // de fromMe, que é o que faltava aqui e trocou a foto de um grupo pela de
      // um participante.
    } catch (err) {
      // Duas mensagens quase simultâneas do mesmo número correm o SELECT acima
      // antes de qualquer INSERT commitar. A constraint leads_org_phone_unique
      // deixa só uma passar; a outra recupera o lead que venceu.
      if (!isUniqueViolation(err)) throw err
      const [existente] = await db
        .select({
          id: leads.id, title: leads.title, phone: leads.phone, stageId: leads.stageId,
          ultimoRemetente: leads.lastMessageSenderType, avatarUrl: leads.avatarUrl,
        })
        .from(leads)
        .where(and(eq(leads.organizationId, orgId), inArray(leads.phone, variantes), isNull(leads.deletedAt)))
        .limit(1)
      if (!existente) throw err
      lead = existente
    }
  }

  /*
   * Foto do contato — só da mensagem que ELE mandou, e só em conversa de uma
   * pessoa só.
   *
   * `senderPhoto` é a foto de QUEM ESCREVEU aquela mensagem, e é aí que mora a
   * pegadinha que já estragou dois registros aqui:
   *
   *   - num GRUPO, quem escreveu é um participante. A foto dele virou a foto do
   *     grupo "Lead Magnet e CRM" — a conversa passou a ostentar o rosto de uma
   *     pessoa que é só um dos membros.
   *   - numa mensagem NOSSA (fromMe, o eco de quem responde pelo celular), quem
   *     escreveu é a empresa. A foto do negócio viraria a foto do cliente.
   *
   * Então: só mensagem que entra (`!isFromMe`), só conversa individual
   * (`!ehGrupo`), e só quando ainda não há foto — quem já tem não gasta
   * requisição. É também o único momento em que essa foto existe pra gente: a
   * listagem de conversas da Z-API não devolve foto nenhuma.
   */
  const fotoDoContato = !isFromMe && !ehGrupo ? (body?.senderPhoto || body?.photo) : null
  if (!lead.avatarUrl && typeof fotoDoContato === 'string' && fotoDoContato) {
    const hospedada = await rehospedarFotoPerfil(orgId, fotoDoContato, phone)
    if (hospedada) await db.update(leads).set({ avatarUrl: hospedada }).where(eq(leads.id, lead.id))
  }

  if (messageId) {
    const recentes = await db
      .select({ id: leadActivities.id, metadata: leadActivities.metadata })
      .from(leadActivities)
      .where(and(eq(leadActivities.organizationId, orgId), eq(leadActivities.leadId, lead.id)))
      .limit(100)
    const duplicada = recentes.find((a: any) => a.metadata?.zapi_message_id === messageId)
    if (duplicada) return { status: 'skipped', reason: 'duplicate' }
  }

  let midiaUrl: string | undefined
  let midiaMime: string | undefined
  if (extraido.mediaUrl && messageId) {
    const hospedada = await rehospedarMidiaZapi(orgId, extraido.mediaUrl, messageId)
    if (hospedada) {
      midiaUrl = hospedada.url
      midiaMime = hospedada.mimetype || extraido.mediaMimetype
    } else {
      // Não conseguiu re-hospedar: usa a original mesmo sabendo que ela expira em
      // 30 dias. Um link temporário é melhor que nenhum — sem isso a mensagem
      // apareceria só como rótulo de texto e a foto se perderia agora, não em 30 dias.
      midiaUrl = extraido.mediaUrl
      midiaMime = extraido.mediaMimetype
    }
  }

  const metadata: Record<string, any> = {
    source: 'zapi',
    direction: isFromMe ? 'outbound' : 'inbound',
    zapi_message_id: messageId,
  }
  if (ehGrupo) {
    metadata.is_group = true
    // Sem isto a conversa de grupo vira um monte de mensagem sem dono e não dá
    // pra saber quem disse o quê.
    if (body?.participantPhone) metadata.participant_phone = String(body.participantPhone)
  }
  if (!isFromMe) metadata.sender_name = senderName
  if (midiaUrl) metadata.media_url = midiaUrl
  if (extraido.mediaType) metadata.media_type = extraido.mediaType
  if (midiaMime) metadata.media_mimetype = midiaMime
  if (extraido.mediaFilename) metadata.media_filename = extraido.mediaFilename
  if (extraido.audioSeconds !== undefined) metadata.audio_seconds = extraido.audioSeconds

  // `momment` vem em milissegundos. Preserva o horário real: webhook reenviado
  // com atraso não pode pular pro topo da conversa como se fosse de agora.
  const momentoMs = typeof body?.momment === 'number' ? body.momment : undefined

  let activity: { id: string }
  try {
    ;[activity] = await db
      .insert(leadActivities)
      .values({
        organizationId: orgId,
        leadId: lead.id,
        type: 'whatsapp',
        content: extraido.text,
        metadata,
        ...(momentoMs ? { createdAt: new Date(momentoMs) } : {}),
      })
      .returning({ id: leadActivities.id })
  } catch (err) {
    // Rede de segurança do índice único global — o dedupe acima só olha as 100
    // últimas atividades DESTE lead.
    if (!isUniqueViolation(err)) throw err
    return { status: 'skipped', reason: 'duplicate' }
  }

  const leadUpdates: Record<string, any> = {
    lastMessageContent: extraido.text,
    lastMessageSenderType: isFromMe ? 'human' : 'lead',
    lastActivityAt: new Date(),
    lastActivityType: 'whatsapp',
    isUnread: !isFromMe,
    ...(!isFromMe ? { isArchived: false } : {}),
    integrationId: integration?.id || null,
  }
  if (!isFromMe) {
    leadUpdates.title = lead.title === lead.phone ? senderName : lead.title
  } else if (lead.stageId && !ehGrupo) {
    // Respondeu pelo celular: o lead está sendo atendido por gente, e a etapa
    // acompanha — mesma regra que já vale pra Evolution.
    //
    // Só vale pra quem JÁ está no funil (`lead.stageId`). Conversa importada
    // nasce sem etapa e precisa continuar assim: responder o fornecedor ou um
    // contato antigo não pode criar card no Kanban — era exatamente a mistura
    // que a importação evita.
    const [stage] = await db
      .select({ id: pipelineStages.id })
      .from(pipelineStages)
      .where(and(
        eq(pipelineStages.organizationId, orgId),
        isNull(pipelineStages.deletedAt),
        ilike(pipelineStages.name, 'Em atendimento')
      ))
      .limit(1)
    if (stage) leadUpdates.stageId = stage.id
  }

  await db.update(leads).set(leadUpdates).where(eq(leads.id, lead.id))

  await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: activity.id })
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
    const textoResposta = extraido.text
    after(() => avisarGrupoRespostaAutomacao(orgId, idDoLead, textoResposta))
  }
  await publishEvent(channels.orgLeads(orgId), events.LEAD_UPDATED, { id: lead.id })

  if (!isFromMe) {
    after(() => notifyInboundMessage(orgId, lead.id, { text: extraido.text, mediaType: extraido.mediaType }))
  }

  await dispatchOutboundWebhook(orgId, {
    leadId: lead.id,
    phone,
    fromMe: isFromMe,
    isGroup: ehGrupo,
    chatLid: null,
    senderName: isFromMe ? null : senderName,
    chatName: lead.title,
    content: extraido.text,
    messageId: messageId || '',
    timestamp: momentoMs ?? Date.now(),
    instanceId: body?.instanceId || integration?.id || null,
    connectedPhone: body?.connectedPhone ? String(body.connectedPhone).replace(/\D/g, '') : null,
    mediaType: extraido.mediaType as any,
    mediaUrl: midiaUrl,
    mediaMimetype: midiaMime,
    mediaFilename: extraido.mediaFilename,
    audioSeconds: extraido.audioSeconds,
  })

  return { status: 'created', activityId: activity.id }
}
