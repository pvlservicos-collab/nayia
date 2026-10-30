import { after } from 'next/server'
import { db } from '@/lib/db'
import { leads, leadActivities, integrations, pipelineStages, webhookLogs } from '@/lib/schema'
import { eq, and, isNull, asc, ilike, inArray, sql } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { dispatchOutboundWebhook } from '@/lib/outbound-webhook'
import { isUniqueViolation } from '@/lib/db-helpers'
import { notifyInboundMessage } from '@/lib/push'
import { avisarGrupoRespostaAutomacao } from '@/lib/avisoGrupo'
import { ZAPI_INTEGRATION_TYPE, TIPOS_ZAPI, rehospedarMidiaZapi, rehospedarFotoPerfil } from '@/lib/zapi'
import { linhaTemTranscricao, transcreverAtividade } from '@/lib/transcricao'
import { ehEspelhoDeTreino, telefoneVariantes, telefoneCanonico } from '@/lib/leadSources'
import { acharLeadDaLinha, type LeadDaLinha } from '@/lib/leadDaLinha'
import { etapaEmAtendimentoDoMesmoPipeline } from '@/lib/etapaDaLinha'
import { contatoDaMensagemNaNay, telefoneDoLidNaNay } from '@/lib/nayLeitura'
import { juntarConversaNaOutra } from '@/lib/juntarConversas'
import { acharCitadas, camposDaCitada } from '@/lib/mensagemCitada'

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
  /** reação: o emoji fica em `text` (vazio = tirou a reação) e vai para cima desta mensagem */
  reacaoA?: string
  /** cartão de contato do WhatsApp: o nome e os números, para o "Criar contato" da conversa */
  contato?: { nome: string; telefones: string[] }
}

/**
 * OS NÚMEROS DO CARTÃO DE CONTATO (Pedro, 30/10/2026: "aparecer o contato na hora que é enviado o card do contato,
 * um cardzinho com a opção Criar contato"). A Z-API manda `phones` e o `vCard`; o vCard tem `waid=` (o número do
 * WhatsApp) ou só o TEL formatado. Os dois juntos, sem repetir.
 */
function telefonesDoContato(c: any): string[] {
  const achados: string[] = []
  for (const p of Array.isArray(c?.phones) ? c.phones : []) achados.push(String(p))
  const vcard = String(c?.vCard || '')
  for (const m of vcard.matchAll(/waid=(\d{8,15})/gi)) achados.push(m[1])
  for (const linha of vcard.split(/\r?\n/)) {
    if (/^(item\d+\.)?TEL/i.test(linha) && !/waid=/i.test(linha)) achados.push(linha.split(':').slice(1).join(':'))
  }
  const limpos = achados.map((t) => t.replace(/\D/g, '')).filter((t) => t.length >= 10 && t.length <= 13)
  return Array.from(new Set(limpos))
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
    const nome = String(body.contact.displayName || body.contact.vCard?.split('FN:')[1]?.split('\n')[0] || 'contato').trim()
    return { text: `👤 Contato compartilhado: ${nome}`, contato: { nome, telefones: telefonesDoContato(body.contact) } }
  }
  if (body?.location) {
    const { latitude, longitude, address } = body.location
    return { text: `📍 Localização: ${address || `${latitude}, ${longitude}`}` }
  }
  if (body?.poll?.question) return { text: `📊 Enquete: ${body.poll.question}` }
  /*
   * REAÇÃO (29/09/2026, "igual ao WhatsApp"): o emoji vai para cima da mensagem
   * reagida, não num balão "Reagiu com 👍" solto. A tela já agrupa assim
   * (is_reaction + target_message_id). Sem a mensagem de referência, fica o
   * balão de antes, para não perder a reação.
   */
  if (body?.reaction) {
    const alvo = body.reaction.referencedMessage?.messageId
    const emoji = String(body.reaction.value || '')
    if (alvo) return { text: emoji, reacaoA: String(alvo) }
    if (emoji) return { text: `Reagiu com ${emoji}` }
    return null
  }
  // mensagem de modelo (com botões), que uma empresa manda
  if (body?.hydratedTemplate) {
    const t = body.hydratedTemplate
    const texto = [t.title, t.message, t.footer].filter((x: unknown) => typeof x === 'string' && x.trim()).join('\n')
    if (texto) return { text: texto }
  }
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
/**
 * O telefone de um @lid: pelo que o CRM já viu (o `chat_lid` que a mensagem
 * DO CONTATO traz) ou pelo que a Nay aprendeu (identidade_lid, migração 167).
 */
async function telefoneDoLid(orgId: string, linhaId: string | null, lid: string): Promise<string | null> {
  if (!lid) return null
  const [visto] = await db
    .select({ phone: leads.phone })
    .from(leads)
    .where(and(
      eq(leads.organizationId, orgId),
      isNull(leads.deletedAt),
      linhaId ? eq(leads.integrationId, linhaId) : sql`true`,
      sql`${leads.customAttributes}->>'chat_lid' = ${lid}`,
      sql`${leads.phone} ~ '^55'`,
    ))
    .limit(1)
  if (visto?.phone) return visto.phone
  try {
    return await telefoneDoLidNaNay(lid)
  } catch (err: any) {
    console.error('[zapi] não consegui perguntar à Nay o telefone do @lid', err?.message || err)
    return null
  }
}

export interface OpcoesDaEntrada {
  /**
   * A conferência com a Nay (espelhoDaNay.ts) traz o que não chegou na hora.
   * É histórico: não notifica ninguém, não avisa grupo, não chama webhook de
   * fora, não marca como não lida e não tira a conversa do lugar na lista.
   */
  silencioso?: boolean
}

export async function processZapiMessage(orgId: string, body: any, opcoes: OpcoesDaEntrada = {}): Promise<ZapiProcessResult> {
  const silencioso = !!opcoes.silencioso
  const messageId: string | undefined = body?.messageId
  // a mensagem que o CRM reentregou à Nay ("Nay voltar a atender") já está
  // na conversa: o eco dela (espelho, conferência) não vira cópia
  if (typeof messageId === 'string' && messageId.startsWith('CRMNAY')) return { status: 'skipped', reason: 'reentrega do CRM à Nay' }
  const phoneBruto: string = String(body?.phone || '')
  const ehGrupo = !!body?.isGroup

  /*
   * O @LID (Pedro, 29/09/2026: "tem mensagem que não aparece").
   *
   * O WhatsApp esconde o telefone de parte dos contatos. A mensagem DELE chega
   * com o telefone e o `chatLid`; a NOSSA (a Nay, o Tel pelo celular, o
   * publicador) chega só com o LID em `phone` ("219958210478302@lid"). Até
   * aqui esse número de 15 dígitos caía na regra de "comunidade" logo abaixo e
   * era jogado fora: em 3 dias, 555 de 755 respostas de texto da Nay e 220 de
   * 242 fotos sumiram da conversa. Agora o LID vira o telefone da pessoa e a
   * mensagem entra na conversa dela; sem telefone conhecido, entra na conversa
   * do LID -- nunca some.
   */
  const ehLid = !ehGrupo && /@lid$/i.test(phoneBruto)
  const lidDoChat = String(body?.chatLid || '').replace(/\D/g, '') || (ehLid ? phoneBruto.replace(/\D/g, '') : '')

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
  let variantes = ehGrupo ? [phoneBruto] : telefoneVariantes(phoneBruto)
  let phone = ehGrupo
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
  if (!ehGrupo && !ehLid && phone.replace(/\D/g, '').length > 14) {
    return { status: 'skipped', reason: 'comunidade/lista de transmissão' }
  }

  // Espelho da bateria de treino não é cliente: a rodada conversa com a Nay pelo
  // fluxo real, e o n8n copia para cá tudo que passa por lá. Sem esta linha o
  // CRM ganha uma conversa falsa por pessoa a cada rodada, com o nome de um
  // corretor de verdade -- foi o que aconteceu em 26/09/2026 (24 leads).
  if (!ehGrupo && ehEspelhoDeTreino(phone)) {
    return { status: 'skipped', reason: 'espelho da bateria de treino' }
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

  // QUAL LINHA Z-API RECEBEU (28/09): a Parceria e a da captação avisam no
  // mesmo endereço; o `instanceId` do aviso diz de qual número veio. Sem ele
  // (ou instância desconhecida), é a Parceria, como sempre foi. Vem antes de
  // tudo porque o lead é procurado DENTRO da linha (ver `leadDaLinha.ts`).
  const instanciaDoAviso = body?.instanceId ? String(body.instanceId) : null
  let [integration] = instanciaDoAviso
    ? await db
        .select({ id: integrations.id, type: integrations.type })
        .from(integrations)
        .where(and(
          eq(integrations.organizationId, orgId),
          inArray(integrations.type, TIPOS_ZAPI),
          isNull(integrations.deletedAt),
          sql`${integrations.config}->>'instance_id' = ${instanciaDoAviso}`
        ))
        .limit(1)
    : []
  if (!integration) {
    ;[integration] = await db
      .select({ id: integrations.id, type: integrations.type })
      .from(integrations)
      .where(and(
        eq(integrations.organizationId, orgId),
        eq(integrations.type, ZAPI_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      ))
      .limit(1)
  }
  const linhaId = integration?.id ?? null

  // o nome de quem recebeu, quando a Nay/captação sabe (título da conversa nova)
  let nomeDoDestino: string | null = null
  if (ehLid) {
    let real = await telefoneDoLid(orgId, linhaId, lidDoChat)
    /*
     * Eco de mensagem NOSSA para quem nunca respondeu (29/09, captação: "tá
     * puxando id e não número"): o LID ninguém conhece ainda, mas o id da
     * mensagem sim -- é o do disparo/envio que a captação e a Nay guardaram.
     */
    if (!real && body?.fromMe && messageId) {
      try {
        const destino = await contatoDaMensagemNaNay(String(messageId))
        if (destino) { real = destino.telefone; nomeDoDestino = destino.nome }
      } catch (err: any) {
        console.error('[zapi] não consegui perguntar à Nay quem recebeu a mensagem', err?.message || err)
      }
    }
    if (real) {
      variantes = telefoneVariantes(real)
      phone = telefoneCanonico(real) || real
    }
  }

  // Grupo que ninguém importou: descarta ANTES de tentar ler o conteúdo, pelo
  // mesmo motivo acima — não tem por que diagnosticar mensagem que ia pro lixo.
  if (ehGrupo) {
    const grupoExiste = await acharLeadDaLinha(orgId, [phone], linhaId)
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
  /*
   * O NOME DO CHAT NA MENSAGEM NOSSA (29/09, captação: "tá puxando id e não
   * número"). Em fromMe o senderName é o nosso, mas o chatName é o contato como
   * está salvo no celular -- é o que o WhatsApp mostra na lista. Para quem o
   * WhatsApp só conhece pelo LID, é o único nome que existe. Quando o contato
   * não está salvo, o chatName vem igual ao LID: aí não serve.
   */
  const nomeDoChat: string | null = (() => {
    const n = typeof body?.chatName === 'string' ? body.chatName.trim() : ''
    return n && !/@lid|@c\.us|^[\d\s+()-]+$/i.test(n) ? n : null
  })()

  // O lead DESTA LINHA (Tel, 28/09: "não misturando contatos"). A mesma pessoa
  // falando com outro número tem outro lead, na aba daquele número.
  const doLead = (l: LeadDaLinha) => ({
    id: l.id, title: l.title, phone: l.phone, stageId: l.stageId,
    // Quem falou por último ANTES desta mensagem: é o que diz se a pessoa
    // está respondendo a automação.
    ultimoRemetente: l.lastMessageSenderType,
    avatarUrl: l.avatarUrl,
  })
  let leadCriadoAgora = false
  const achado = await acharLeadDaLinha(orgId, variantes, linhaId)
  let lead = achado ? doLead(achado) : undefined

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
            : (isFromMe ? (nomeDoDestino || nomeDoChat || phone) : (senderName || phone)),
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
          // na conferência (histórico), a conversa nasce na hora da mensagem --
          // senão pularia para o topo da lista sem prévia nenhuma
          lastActivityAt: silencioso && typeof body?.momment === 'number' ? new Date(body.momment - 1) : new Date(),
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
      // (telefone + linha) deixa só uma passar; a outra recupera o que venceu.
      if (!isUniqueViolation(err)) throw err
      const existente = await acharLeadDaLinha(orgId, variantes, linhaId)
      if (!existente) throw err
      lead = doLead(existente)
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
    // depois de mostrar a mensagem (Pedro, 29/09: "mostra logo e depois...")
    const idDoLead = lead.id
    after(async () => {
      try {
        const hospedada = await rehospedarFotoPerfil(orgId, fotoDoContato, phone)
        if (hospedada) await db.update(leads).set({ avatarUrl: hospedada }).where(eq(leads.id, idDoLead))
      } catch (err: any) {
        console.error('[zapi] foto de perfil', err?.message || err)
      }
    })
  }

  // O LID desta pessoa fica no lead: a próxima mensagem NOSSA para ela (que
  // chega só com o LID) acha a conversa sem precisar perguntar à Nay.
  if (lidDoChat && !ehGrupo && /^55/.test(String(lead.phone || ''))) {
    try {
      await db.execute(sql`
        UPDATE leads
           SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('chat_lid', ${lidDoChat}::text)
         WHERE id = ${lead.id} AND coalesce(custom_attributes->>'chat_lid', '') <> ${lidDoChat}`)
    } catch (err) {
      console.error('[zapi] não gravei o chat_lid', err)
    }
    /*
     * A conversa que nasceu só com o LID (nossas mensagens antes de sabermos o
     * número) é desta pessoa: o próprio WhatsApp acabou de dizer (telefone +
     * chatLid na mesma mensagem). Junta aqui, na mesma linha (29/09).
     */
    try {
      const velha = await db.execute(sql`
        SELECT id FROM leads
         WHERE organization_id = ${orgId} AND integration_id IS NOT DISTINCT FROM ${linhaId}
           AND deleted_at IS NULL AND id <> ${lead.id} AND phone = ${lidDoChat}
         LIMIT 1`)
      const idVelha = (velha.rows[0] as { id?: string } | undefined)?.id
      if (idVelha) await juntarConversaNaOutra(idVelha, lead.id)
    } catch (err) {
      console.error('[zapi] não juntei a conversa do @lid', err)
    }
  }

  /*
   * MENSAGEM EDITADA (29/09/2026): no WhatsApp ela fica com o texto novo e a
   * marca "Editada". A Z-API avisa com `isEdit`; se a mensagem já está aqui,
   * troca o texto dela em vez de parar no "duplicada" (que deixava o texto velho).
   */
  if (body?.isEdit === true && messageId && !extraido.reacaoA && extraido.text) {
    const [original] = await db
      .select({ id: leadActivities.id, leadId: leadActivities.leadId })
      .from(leadActivities)
      .where(and(
        eq(leadActivities.organizationId, orgId),
        sql`${leadActivities.metadata}->>'zapi_message_id' = ${messageId}`))
      .limit(1)
    if (original) {
      await db.execute(sql`
        UPDATE lead_activities
           SET content = ${extraido.text},
               metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('editada', true)
         WHERE id = ${original.id}`)
      if (!silencioso) await publishEvent(channels.leadActivities(original.leadId), events.ACTIVITY_UPDATED, { id: original.id })
      return { status: 'skipped', reason: 'edição aplicada' }
    }
  }

  // Duplicada: pelo índice único do id da Z-API (29/09). Antes lia 100
  // mensagens da conversa, sem ordem, e comparava em memória.
  if (messageId) {
    const ja = await db.execute(sql`
      SELECT 1 FROM lead_activities WHERE metadata->>'zapi_message_id' = ${messageId} LIMIT 1`)
    if (ja.rows.length) return { status: 'skipped', reason: 'duplicate' }
  }

  /*
   * MOSTRA LOGO, GUARDA DEPOIS (Pedro, 29/09/2026: "preciso do máximo de
   * velocidade nas mensagens no CRM, mostra logo e depois faz testes, métricas,
   * organiza, transcreve"). A mensagem entra com o link da Z-API (vale 30 dias)
   * e aparece na hora; a cópia no armazém do CRM e a transcrição vêm em
   * seguida, e a tela recebe a troca do link pelo 'activity.updated'. Antes o
   * download (1 a 5 s) segurava a mensagem.
   */
  const midiaUrl: string | undefined = extraido.mediaUrl || undefined
  const midiaMime: string | undefined = extraido.mediaMimetype

  const metadata: Record<string, any> = {
    source: 'zapi',
    direction: isFromMe ? 'outbound' : 'inbound',
    zapi_message_id: messageId,
    // por qual número passou -- é o que põe a conversa na aba certa, mesmo quando
    // a mesma pessoa fala com os dois números
    channel: integration?.type || ZAPI_INTEGRATION_TYPE,
  }
  // Mensagem nossa que NÃO saiu pela API: alguém escreveu no celular. As barrinhas ficam rosa (Pedro, 25/10).
  if (isFromMe && body?.fromApi === false) metadata.do_celular = true
  if (ehGrupo) {
    metadata.is_group = true
    // Sem isto a conversa de grupo vira um monte de mensagem sem dono e não dá
    // pra saber quem disse o quê.
    if (body?.participantPhone) metadata.participant_phone = String(body.participantPhone)
  }
  /*
   * A MENSAGEM CITADA (Tel, 26/09/2026): "quando eu marcar uma mensagem de um
   * grupo apareça a mensagem lá no número lá no crm... apareça minha mensagem
   * completa: Lead se refere a mensagem: (CONTEUDO DA MENSAGEM)".
   *
   * A Z-API manda só o ID do que foi citado, nunca o texto -- está anotado no
   * próprio fluxo da Nay ("so o ID chega, nunca o texto", medido em 01/09).
   * Mas nós guardamos o `zapi_message_id` de cada mensagem, então o texto se
   * acha procurando por ele.
   *
   * 09/10/2026: o que não está no CRM se procura no banco da Nay (o card e a
   * lista do grupo, a foto do post, o que ela mandou) -- ver mensagemCitada.ts.
   *
   * Não achou em lugar nenhum (citou algo de antes do CRM, ou de um grupo que
   * não é nosso)? Guarda só o ID: a tela avisa que ele respondeu citando
   * algo, sem inventar conteúdo, e tenta de novo quando a conversa for aberta.
   */
  const idCitado = body?.referenceMessageId
    || body?.referencedMessage?.messageId
    || null
  if (idCitado) {
    metadata.quoted_message_id = String(idCitado)
    // procurar a citada nunca derruba a gravação da mensagem nova (acharCitadas não levanta erro)
    const citada = (await acharCitadas(orgId, [String(idCitado)])).get(String(idCitado))
    if (citada) Object.assign(metadata, camposDaCitada(citada))
  }

  if (!isFromMe) metadata.sender_name = senderName
  if (extraido.reacaoA) {
    metadata.is_reaction = true
    metadata.target_message_id = extraido.reacaoA
  }
  if (body?.isEdit === true) metadata.editada = true
  if (midiaUrl) metadata.media_url = midiaUrl
  if (extraido.mediaType) metadata.media_type = extraido.mediaType
  if (midiaMime) metadata.media_mimetype = midiaMime
  if (extraido.mediaFilename) metadata.media_filename = extraido.mediaFilename
  if (extraido.audioSeconds !== undefined) metadata.audio_seconds = extraido.audioSeconds
  if (extraido.contato) {
    metadata.contato_compartilhado = extraido.contato
    // sem número achado, o cartão como veio fica guardado: é por ele que se descobre o porquê
    if (!extraido.contato.telefones.length) metadata.contato_bruto = body.contact
  }

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

  if (extraido.mediaUrl && messageId) {
    const idAtividade = activity.id
    const idDoLead = lead.id
    const urlOriginal = extraido.mediaUrl
    const idDaMensagem = messageId
    // a transcrição da entrada normal; a da conferência sai pelo acordarAsConversas
    const transcrever = !silencioso && extraido.mediaType === 'audio'
      && linhaTemTranscricao(integration?.type || ZAPI_INTEGRATION_TYPE)
    after(async () => {
      try {
        const hospedada = await rehospedarMidiaZapi(orgId, urlOriginal, idDaMensagem)
        if (hospedada) {
          await db.execute(sql`
            UPDATE lead_activities
               SET metadata = metadata || jsonb_build_object('media_url', ${hospedada.url}::text)
                              || CASE WHEN ${hospedada.mimetype ?? null}::text IS NOT NULL
                                      THEN jsonb_build_object('media_mimetype', ${hospedada.mimetype ?? null}::text)
                                      ELSE '{}'::jsonb END
             WHERE id = ${idAtividade}`)
          await publishEvent(channels.leadActivities(idDoLead), events.ACTIVITY_UPDATED, { id: idAtividade })
        }
      } catch (err: any) {
        console.error('[zapi] guardar a mídia', idAtividade, err?.message || err)
      }
      if (transcrever) {
        await transcreverAtividade(idAtividade).catch((e) => console.error('[transcricao]', idAtividade, e?.message || e))
      }
    })
  }

  // Tirar a reação não mexe na lista (como no WhatsApp); a tela aberta só
  // precisa saber que o emoji saiu.
  if (extraido.reacaoA && !extraido.text) {
    if (!silencioso) await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: activity.id })
    return { status: 'created', activityId: activity.id }
  }
  // na lista, a reação aparece como no WhatsApp: "Reagiu com 👍"
  const previa = extraido.reacaoA ? `Reagiu com ${extraido.text}` : extraido.text

  const leadUpdates: Record<string, any> = {
    lastMessageContent: previa,
    lastMessageSenderType: isFromMe ? 'human' : 'lead',
    lastActivityAt: new Date(),
    lastActivityType: 'whatsapp',
    // reação não deixa a conversa "não lida" -- nem apaga a marca que já estava
    ...(extraido.reacaoA ? {} : { isUnread: !isFromMe }),
    ...(!isFromMe ? { isArchived: false } : {}),
    // A linha do lead NÃO muda aqui (28/09). Antes esta linha puxava o lead
    // para o número da última mensagem, e era isso que fazia a conversa pular
    // de aba e a resposta sair pelo número errado.
  }
  if (!isFromMe) {
    leadUpdates.title = lead.title === lead.phone ? senderName : lead.title
  } else if (nomeDoChat && !ehGrupo && lead.title === lead.phone) {
    leadUpdates.title = nomeDoChat
  }
  if (isFromMe && lead.stageId && !ehGrupo) {
    // Respondeu pelo celular: o lead está sendo atendido por gente, e a etapa
    // acompanha — mesma regra que já vale pra Evolution.
    //
    // Só vale pra quem JÁ está no funil (`lead.stageId`). Conversa importada
    // nasce sem etapa e precisa continuar assim: responder o fornecedor ou um
    // contato antigo não pode criar card no Kanban — era exatamente a mistura
    // que a importação evita. E só dentro do pipeline dele, para a frente
    // (28/09, ver `etapaEmAtendimentoDoMesmoPipeline`).
    const etapa = await etapaEmAtendimentoDoMesmoPipeline(orgId, lead.stageId)
    if (etapa) leadUpdates.stageId = etapa
  }

  if (silencioso) {
    // Histórico que faltava: só conta como "última mensagem" se for mesmo a
    // mais nova da conversa; não mexe em não lida, arquivo nem etapa. O título
    // só troca como na entrada normal: se ainda é o número, vira o nome de quem
    // escreveu.
    const quando = new Date(momentoMs ?? Date.now())
    const nomeNovo = !ehGrupo ? (!isFromMe ? (senderName !== phone ? senderName : null) : nomeDoChat) : null
    if (nomeNovo) {
      await db.execute(sql`
        UPDATE leads SET title = ${nomeNovo}
         WHERE id = ${lead.id} AND title IS NOT DISTINCT FROM phone`)
    }
    await db.execute(sql`
      UPDATE leads
         SET last_message_content = ${previa},
             last_message_sender_type = ${isFromMe ? 'human' : 'lead'},
             last_activity_at = ${quando.toISOString()}::timestamptz,
             last_activity_type = 'whatsapp'
       WHERE id = ${lead.id}
         AND (last_activity_at IS NULL OR last_activity_at < ${quando.toISOString()}::timestamptz)`)
    return { status: 'created', activityId: activity.id }
  }

  /*
   * A ÚLTIMA MENSAGEM É A MAIS NOVA PELA HORA DA MENSAGEM (Pedro, 29/09/2026:
   * "não está contando as pessoas que eu respondo pelo app, e fica gente como
   * não respondido"). A entrada ao vivo gravava a hora do PROCESSAMENTO: a
   * mensagem da pessoa chega ao CRM ~60 s depois (o espelho roda depois da IA);
   * quem respondia pelo celular nesse meio-tempo tinha a resposta gravada com a
   * hora real -- "mais velha" que a pergunta -- e a conversa ficava como se a
   * pessoa tivesse falado por último. Agora vale a hora da mensagem, e a
   * "última mensagem" (e o não lida) só troca se esta for mesmo a mais nova --
   * a mesma regra da conferência. Título, etapa e desarquivar seguem como antes.
   */
  const quandoDaMensagem = new Date(momentoMs ?? Date.now())
  const { lastMessageContent: _c, lastMessageSenderType: _s, lastActivityAt: _a, lastActivityType: _t, isUnread, ...outrasMudancas } = leadUpdates
  if (Object.keys(outrasMudancas).length) await db.update(leads).set(outrasMudancas).where(eq(leads.id, lead.id))
  await db.execute(sql`
    UPDATE leads
       SET last_message_content = ${previa},
           last_message_sender_type = ${isFromMe ? 'human' : 'lead'},
           last_activity_at = ${quandoDaMensagem.toISOString()}::timestamptz,
           last_activity_type = 'whatsapp',
           is_unread = CASE WHEN ${typeof isUnread === 'boolean'}::boolean THEN ${isUnread === true}::boolean ELSE is_unread END
     WHERE id = ${lead.id}
       AND (last_activity_at IS NULL OR last_activity_at <= ${quandoDaMensagem.toISOString()}::timestamptz)`)

  await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: activity.id })

  // A TRANSCRIÇÃO DO ÁUDIO: na corrente que guarda a mídia, logo depois de gravar.

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
    const textoResposta = previa
    after(() => avisarGrupoRespostaAutomacao(orgId, idDoLead, textoResposta))
  }
  await publishEvent(channels.orgLeads(orgId), events.LEAD_UPDATED, { id: lead.id })

  if (!isFromMe) {
    after(() => notifyInboundMessage(orgId, lead.id, { text: previa, mediaType: extraido.mediaType }))
  }

  await dispatchOutboundWebhook(orgId, {
    leadId: lead.id,
    phone,
    fromMe: isFromMe,
    isGroup: ehGrupo,
    chatLid: null,
    senderName: isFromMe ? null : senderName,
    chatName: lead.title,
    content: previa,
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
