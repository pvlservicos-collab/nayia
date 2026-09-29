/**
 * A CONFERÊNCIA COM A NAY (Pedro, 29/09/2026: "as conversas da parceria eu
 * preciso que fique exatamente como está no meu whatsapp aqui ... tem mensagem
 * que não aparece").
 *
 * A conversa da Parceria chega ao CRM por um espelho no fluxo da NAI no n8n.
 * Medido em 29/09, o que não chegava:
 *   - o que não passa pela NAI: comando do Tel, card e fotos que o publicador
 *     manda, mensagem da equipe -- o espelho mora só no fluxo da NAI;
 *   - o que chegou com o CRM fora do ar (publicação, reinício): o espelho não
 *     tenta de novo.
 * (O terceiro buraco, as respostas para contato com @lid, era o CRM jogando
 * fora -- consertado na entrada, ver zapiInbound.ts.)
 *
 * A Nay registra TODA mensagem do número da Parceria (tabela `mensagens`, com o
 * id da Z-API). Esta conferência lê esse registro num intervalo, vê o que o CRM
 * ainda não tem pelo id, e passa pela mesma entrada da Z-API (processZapiMessage)
 * em modo silencioso: sem notificação, sem aviso, sem "não lida".
 *
 * Roda a cada minuto olhando os últimos 40 minutos (/api/cron/espelho-nay), e
 * uma vez para trás desde que o CRM existe (25/09).
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { mensagensDaCaptacao, mensagensDaParceria, type MensagemDaParceria } from '@/lib/nayLeitura'
import { processZapiMessage } from '@/lib/zapiInbound'
import { ehEspelhoDeTreino } from '@/lib/leadSources'
import { publishEvent, channels, events } from '@/lib/realtime'
import { transcreverEmSegundoPlano } from '@/lib/transcricao'
import { notifyInboundMessage } from '@/lib/push'

export interface ResultadoDaConferencia {
  desde: string
  ate: string
  naNay: number
  jaTinha: number
  trazidas: number
  puladas: Record<string, number>
  erros: number
}

function nomeDoArquivo(url: string | null): string | undefined {
  const nome = String(url || '').split('?')[0].split('/').pop()
  return nome && /\.[a-z0-9]{2,5}$/i.test(nome) ? decodeURIComponent(nome) : undefined
}

/** A mensagem do registro da Nay no formato do aviso da Z-API. */
export function payloadDaMensagem(m: MensagemDaParceria): any | null {
  const deNos = m.direcao === 'enviada'
  const texto = m.texto && m.texto !== 'null' ? m.texto : ''
  const body: any = {
    type: 'ReceivedCallback',
    phone: m.telefone,
    fromMe: deNos,
    fromApi: deNos,
    messageId: m.messageId,
    momment: new Date(m.criadaEm).getTime(),
    isGroup: false,
    ...(!deNos && m.nome ? { senderName: m.nome } : {}),
    ...(m.citadoId ? { referenceMessageId: m.citadoId } : {}),
  }
  switch (m.origem) {
    case 'texto':
      if (!texto) return null
      body.text = { message: texto }
      break
    case 'imagem':
      if (m.midia) body.image = { imageUrl: m.midia, ...(texto ? { caption: texto } : {}) }
      else body.text = { message: texto || '📷 Imagem' }
      break
    case 'figurinha':
      if (m.midia) body.sticker = { stickerUrl: m.midia }
      else body.text = { message: '✨ Figurinha' }
      break
    case 'audio':
      if (m.midia) body.audio = { audioUrl: m.midia, ...(m.duracao ? { seconds: m.duracao } : {}) }
      else body.text = { message: '🎵 Áudio' }
      break
    case 'video':
      if (m.midia) body.video = { videoUrl: m.midia, ...(texto ? { caption: texto } : {}) }
      else body.text = { message: texto || '🎥 Vídeo' }
      break
    case 'documento':
      if (m.midia) body.document = { documentUrl: m.midia, fileName: nomeDoArquivo(m.midia), ...(texto ? { caption: texto } : {}) }
      else body.text = { message: texto || '📄 Documento' }
      break
    default:
      // reação e "outro" vêm sem conteúdo no registro da Nay: não há o que mostrar
      if (!texto) return null
      body.text = { message: texto }
  }
  return body
}

let rodando = false

/** A função da Nay devolve no máximo isto por chamada; o resto vem na próxima página. */
const POR_PAGINA = 5000

export interface OpcoesDaConferencia {
  /**
   * A rodada de cada minuto (não o histórico): o que ela traz é de agora, então
   * a conversa acorda como no WhatsApp -- a tela aberta recebe a mensagem, a
   * conversa fica "não lida" se a última palavra é da pessoa, e o áudio ganha a
   * transcrição. No histórico nada disso: é passado, já foi visto no celular.
   */
  aoVivo?: boolean
}

export async function conferirComANay(
  organizacao: string, desde: Date, ate: Date, opcoes: OpcoesDaConferencia = {},
): Promise<ResultadoDaConferencia | null> {
  if (rodando) return null
  rodando = true
  const r: ResultadoDaConferencia = { desde: desde.toISOString(), ate: ate.toISOString(), naNay: 0, jaTinha: 0, trazidas: 0, puladas: {}, erros: 0 }
  const pular = (motivo: string) => { r.puladas[motivo] = (r.puladas[motivo] ?? 0) + 1 }
  const criadas: Array<{ atividade: string; recebida: boolean; audio: boolean }> = []
  const vistas = new Set<string>()
  try {
    let inicio = desde
    for (;;) {
      const pagina = await mensagensDaParceria(inicio, ate, POR_PAGINA)
      // a página seguinte recomeça no horário da última: as do mesmo instante
      // voltam e são reconhecidas pelo id
      const mensagens = pagina.filter((m) => !vistas.has(m.messageId))
      mensagens.forEach((m) => vistas.add(m.messageId))
      r.naNay += mensagens.length

      if (mensagens.length) {
        const ids = mensagens.map((m) => m.messageId)
        const existentes = await db.execute(sql`
          SELECT metadata->>'zapi_message_id' AS id FROM lead_activities
           WHERE metadata->>'zapi_message_id' IN (SELECT jsonb_array_elements_text(${JSON.stringify(ids)}::jsonb))`)
        const tem = new Set((existentes.rows as Array<{ id: string }>).map((x) => x.id))

        for (const m of mensagens) {
          if (tem.has(m.messageId)) { r.jaTinha++; continue }
          if (ehEspelhoDeTreino(m.telefone)) { pular('espelho da bateria de treino'); continue }
          const body = payloadDaMensagem(m)
          if (!body) { pular(`sem conteúdo (${m.origem})`); continue }
          try {
            const res = await processZapiMessage(organizacao, body, { silencioso: true })
            if (res.status === 'created') {
              r.trazidas++
              criadas.push({ atividade: res.activityId, recebida: m.direcao !== 'enviada', audio: !!body.audio })
            } else pular(res.reason)
          } catch (err: any) {
            r.erros++
            console.error('[espelho da Nay]', m.messageId, err?.message || err)
          }
        }
      }

      if (pagina.length < POR_PAGINA) break
      const ultima = new Date(pagina[pagina.length - 1].criadaEm)
      // mais de uma página inteira no mesmo instante não acontece; se acontecer,
      // para em vez de girar em falso
      if (ultima.getTime() <= inicio.getTime()) break
      inicio = ultima
    }

    if (criadas.length && opcoes.aoVivo) await acordarAsConversas(organizacao, criadas)
    if (r.trazidas > 0) await avisarAsListas(organizacao, criadas)
    return r
  } finally {
    rodando = false
  }
}

/**
 * A lista das telas abertas: QUAIS conversas mudaram (29/09). Com o `id: null`
 * de antes, cada rodada fazia cada tela baixar a lista inteira (400 KB); com os
 * ids, a tela busca só essas.
 */
async function avisarAsListas(organizacao: string, criadas: Array<{ atividade: string }>) {
  try {
    const r = await db.execute(sql`
      SELECT DISTINCT lead_id::text AS lead FROM lead_activities
       WHERE id IN (SELECT (jsonb_array_elements_text(${JSON.stringify(criadas.map((c) => c.atividade))}::jsonb))::uuid)`)
    const ids = (r.rows as Array<{ lead: string }>).map((x) => x.lead)
    await publishEvent(channels.orgLeads(organizacao), events.LEAD_UPDATED, { id: null, ids: ids.slice(0, 200), conferencia: true })
  } catch (err: any) {
    console.error('[espelho da Nay] não avisei as listas', err?.message || err)
  }
}

/** Para a rodada de cada minuto: o que a entrada normal faria, menos avisos e webhooks. */
async function acordarAsConversas(organizacao: string, criadas: Array<{ atividade: string; recebida: boolean; audio: boolean }>) {
  const todas = JSON.stringify(criadas.map((c) => c.atividade))
  const recebidas = JSON.stringify(criadas.filter((c) => c.recebida).map((c) => c.atividade))
  try {
    // "não lida" só quando a mensagem trazida é a última da conversa e é da
    // pessoa -- uma mensagem velha que faltava não desfaz a leitura de quem já
    // abriu a conversa
    //
    // 29/09 (Pedro: "algumas conversas não chegam, ou não atualiza rápido"):
    // o que o espelho faria e faltava aqui -- a conversa arquivada volta, e
    // quem tem o CRM aberto recebe a notificação. Só quando a trazida é a
    // última da conversa, é da pessoa e é recente (não notifica o passado).
    const acordadas = await db.execute(sql`
      UPDATE leads l SET is_unread = true, is_archived = false
        FROM lead_activities a
       WHERE a.id IN (SELECT (jsonb_array_elements_text(${recebidas}::jsonb))::uuid)
         AND l.id = a.lead_id
         AND l.last_activity_at = a.created_at
         AND l.last_message_sender_type = 'lead'
         AND (coalesce(l.is_unread, false) = false OR coalesce(l.is_archived, false))
      RETURNING l.id::text AS lead, a.content, a.metadata->>'media_type' AS tipo, a.created_at > now() - interval '10 minutes' AS recente`)
    for (const x of acordadas.rows as Array<{ lead: string; content: string | null; tipo: string | null; recente: boolean }>) {
      if (x.recente) void notifyInboundMessage(organizacao, x.lead, { text: x.content, mediaType: x.tipo }).catch(() => undefined)
    }
    // a resposta NOSSA que é a última da conversa deixa a conversa lida, como
    // na entrada normal (e no WhatsApp quando se responde pelo celular)
    const enviadas = JSON.stringify(criadas.filter((c) => !c.recebida).map((c) => c.atividade))
    await db.execute(sql`
      UPDATE leads l SET is_unread = false
        FROM lead_activities a
       WHERE a.id IN (SELECT (jsonb_array_elements_text(${enviadas}::jsonb))::uuid)
         AND l.id = a.lead_id
         AND l.last_activity_at = a.created_at
         AND l.last_message_sender_type IS DISTINCT FROM 'lead'
         AND coalesce(l.is_unread, false) = true`)
    const conversas = await db.execute(sql`
      SELECT DISTINCT lead_id::text AS lead FROM lead_activities
       WHERE id IN (SELECT (jsonb_array_elements_text(${todas}::jsonb))::uuid)`)
    for (const { lead } of conversas.rows as Array<{ lead: string }>) {
      await publishEvent(channels.leadActivities(lead), events.ACTIVITY_CREATED, { conferencia: true })
    }
  } catch (err: any) {
    console.error('[espelho da Nay] não acordei as conversas', err?.message || err)
  }
  for (const c of criadas) if (c.audio) transcreverEmSegundoPlano(c.atividade)
}

/*
 * A CONFERÊNCIA DA CAPTAÇÃO (Pedro, 29/09/2026: "vê erros nas mensagens na
 * captação, engoliu outra mensagem do Jeferson"). O espelho do fluxo da
 * captação (VPS2) roda DEPOIS do atendimento: um erro no caminho (a OpenAI sem
 * crédito) para a execução e a mensagem não chega; o CRM reiniciando, também.
 * Medido: 25 de 62 textos recebidos faltavam desde que a aba existe.
 *
 * Lê o registro da captação (crm_captacao_mensagens, migração 177) e traz o que
 * falta pela entrada da Z-API, na linha da captação (o instanceId dela):
 *   - ENVIADA: pelo id da Z-API, como na Parceria;
 *   - RECEBIDA: a captação não guarda o id. Já está no CRM se a mesma pessoa
 *     tem, a menos de 3 min, a mesma mensagem (texto igual; áudio/foto/
 *     documento pelo tipo). Senão entra com o id CAPT<id do registro>, que a
 *     rodada seguinte reconhece.
 * Reação e "outro" vêm sem conteúdo: ficam de fora. Mídia recebida que faltava
 * entra só como rótulo -- o registro da captação não guarda o arquivo.
 */
let rodandoCaptacao = false
const ROTULO_DA_MIDIA: Record<string, string> = { audio: '🎵 Áudio', imagem: '📷 Imagem', documento: '📄 Documento', video: '🎥 Vídeo' }
const TIPO_DA_MIDIA: Record<string, string> = { audio: 'audio', imagem: 'image', documento: 'document', video: 'video' }
const TOLERANCIA_MS = 180_000
const REPETIDA_NO_REGISTRO_MS = 15_000
const normalizado = (s: string | null | undefined) => String(s ?? '').replace(/\s+/g, ' ').trim().toLowerCase()

export async function conferirACaptacao(
  organizacao: string, desde: Date, ate: Date, opcoes: OpcoesDaConferencia = {},
): Promise<ResultadoDaConferencia | null> {
  if (rodandoCaptacao) return null
  rodandoCaptacao = true
  const r: ResultadoDaConferencia = { desde: desde.toISOString(), ate: ate.toISOString(), naNay: 0, jaTinha: 0, trazidas: 0, puladas: {}, erros: 0 }
  const pular = (motivo: string) => { r.puladas[motivo] = (r.puladas[motivo] ?? 0) + 1 }
  const criadas: Array<{ atividade: string; recebida: boolean; audio: boolean }> = []
  try {
    const linhas = await db.execute(sql`
      SELECT id::text AS id, config->>'instance_id' AS instancia FROM integrations
       WHERE organization_id = ${organizacao} AND type = 'whatsapp_zapi_captacao' AND deleted_at IS NULL
       LIMIT 1`)
    const linha = linhas.rows[0] as { id: string; instancia: string | null } | undefined
    if (!linha?.instancia) return r

    const mensagens = await mensagensDaCaptacao(desde, ate)
    r.naNay = mensagens.length
    if (!mensagens.length) return r

    const ids = mensagens.map((m) => m.messageId).filter((x): x is string => !!x)
    ids.push(...mensagens.map((m) => `CAPT${m.id}`))
    const existentes = await db.execute(sql`
      SELECT metadata->>'zapi_message_id' AS id FROM lead_activities
       WHERE metadata->>'zapi_message_id' IN (SELECT jsonb_array_elements_text(${JSON.stringify(ids)}::jsonb))`)
    const tem = new Set((existentes.rows as Array<{ id: string }>).map((x) => x.id))

    // o que a pessoa mandou na linha da captação, com folga nas pontas da janela
    const recebidasNoCrm = await db.execute(sql`
      SELECT right(regexp_replace(l.phone, '[^0-9]', '', 'g'), 8) AS fim8,
             coalesce(l.custom_attributes->>'chat_lid', '') AS lid,
             a.content, a.metadata->>'media_type' AS tipo, a.created_at
        FROM lead_activities a JOIN leads l ON l.id = a.lead_id
       WHERE l.integration_id = ${linha.id}::uuid
         AND a.metadata->>'direction' = 'inbound'
         AND a.created_at >= ${new Date(desde.getTime() - TOLERANCIA_MS).toISOString()}::timestamptz
         AND a.created_at < ${new Date(ate.getTime() + TOLERANCIA_MS).toISOString()}::timestamptz`)
    const jaNoCrm = (recebidasNoCrm.rows as Array<{ fim8: string; lid: string; content: string | null; tipo: string | null; created_at: string | Date }>)
      .map((x) => ({ fim8: x.fim8, lid: x.lid, texto: normalizado(x.content), tipo: x.tipo || '', em: new Date(x.created_at).getTime() }))

    // o registro grava a mesma recebida mais de uma vez, em segundos (as três
    // "ficou doente" de 29/09 em 12 s); quem manda duas vezes leva mais que
    // isso (os dois áudios do Jeferson, 25 s)
    const ultimaDoRegistro = new Map<string, number>()

    for (const m of mensagens) {
      if (m.origem === 'reacao' || m.origem === 'outro') { pular(`sem conteúdo (${m.origem})`); continue }
      if (ehEspelhoDeTreino(m.telefone)) { pular('espelho da bateria de treino'); continue }
      if (m.direcao !== 'enviada') {
        const chave = `${m.telefone}|${m.origem}|${normalizado(m.texto)}`
        const antes = ultimaDoRegistro.get(chave)
        const agora = Date.parse(m.criadaEm)
        ultimaDoRegistro.set(chave, agora)
        if (antes !== undefined && agora - antes < REPETIDA_NO_REGISTRO_MS) { pular('repetida no registro'); continue }
      }
      const texto = (m.texto ?? '').trim()
      const rotulo = ROTULO_DA_MIDIA[m.origem]
      if (!texto && !rotulo) { pular('sem conteúdo'); continue }
      const deNos = m.direcao === 'enviada'
      const quando = Date.parse(m.criadaEm)

      if (deNos) {
        if (!m.messageId) { pular('enviada sem id'); continue }
        if (tem.has(m.messageId)) { r.jaTinha++; continue }
      } else {
        if (tem.has(`CAPT${m.id}`)) { r.jaTinha++; continue }
        const fim8 = m.telefone.slice(-8)
        const tipo = TIPO_DA_MIDIA[m.origem]
        const alvo = normalizado(texto)
        // cada mensagem do CRM responde por UMA do registro: dois áudios da
        // mesma pessoa em 3 min são dois (29/09, 10:16:07 e 10:16:32 viravam um)
        const achou = jaNoCrm.findIndex((c) =>
          (c.fim8 === fim8 || c.lid === m.telefone)
          && Math.abs(c.em - quando) < TOLERANCIA_MS
          && (tipo ? c.tipo === tipo : c.texto === alvo))
        if (achou >= 0) { jaNoCrm.splice(achou, 1); r.jaTinha++; continue }
      }

      const body: any = {
        type: 'ReceivedCallback',
        instanceId: linha.instancia,
        phone: m.telefone.startsWith('55') ? m.telefone : `${m.telefone}@lid`,
        fromMe: deNos,
        isGroup: false,
        messageId: deNos ? m.messageId : `CAPT${m.id}`,
        momment: quando,
        text: { message: texto || rotulo },
        ...(!deNos && m.nome ? { senderName: m.nome } : {}),
      }
      try {
        const res = await processZapiMessage(organizacao, body, { silencioso: true })
        if (res.status === 'created') {
          r.trazidas++
          tem.add(body.messageId)
          criadas.push({ atividade: res.activityId, recebida: !deNos, audio: false })
        } else pular(res.reason)
      } catch (err: any) {
        r.erros++
        console.error('[conferência da captação]', m.id, err?.message || err)
      }
    }

    if (criadas.length && opcoes.aoVivo) await acordarAsConversas(organizacao, criadas)
    if (r.trazidas > 0) await avisarAsListas(organizacao, criadas)
    return r
  } finally {
    rodandoCaptacao = false
  }
}
