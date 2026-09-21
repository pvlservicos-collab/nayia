/**
 * Cliente da Z-API — o canal por onde SAI todo disparo e toda automação.
 *
 * Z-API é WhatsApp não oficial: uma sessão de WhatsApp Web conectada por QR code,
 * igual à Evolution que já existe aqui. As duas convivem de propósito — a Evolution
 * fica com um número (conversa manual) e a Z-API com o outro, e é a Z-API que o
 * funil e os disparos usam sempre (ver getAutomationAdapter em channels/registry).
 *
 * Diferenças que moldaram este arquivo:
 *
 *   - Autenticação em até TRÊS pedaços: instanceId e instanceToken vão na própria
 *     URL, e o Client-Token (segurança da CONTA, não da instância) vai no cabeçalho
 *     — obrigatório só se a conta tiver a trava de segurança ligada no painel.
 *   - Mídia recebida vem em URL pública, mas a Z-API só guarda o arquivo por
 *     30 DIAS. Por isso `rehospedarMidia`: sem re-hospedar, toda foto do chat
 *     vira link quebrado um mês depois — e ninguém repara até precisar dela.
 *   - Não existe endpoint de histórico. `buscarConversas` (/chats) traz a LISTA
 *     de conversas, sem mensagem nenhuma; é o máximo que dá pra importar.
 */
import { db } from './db'
import { integrations, integrationSecrets } from './schema'
import { eq, and, isNull } from 'drizzle-orm'
import { telefoneVariantes } from './leadSources'
import { convertAudioToVoiceNote } from './audioConvert'

export const ZAPI_INTEGRATION_TYPE = 'whatsapp_zapi'
export const ZAPI_INTEGRATION_NAME = 'WhatsApp Z-API'

const BASE = 'https://api.z-api.io/instances'

export interface ZapiCredentials {
  integrationId: string
  instanceId: string
  instanceToken: string
  /**
   * Token de segurança da CONTA (Admin → Segurança no painel da Z-API).
   *
   * Opcional de propósito: a Z-API só exige esse cabeçalho quando a conta tem a
   * trava de segurança ligada. Exigir sempre — como a documentação dá a entender
   * — impediria de configurar uma conta que ainda não ativou a trava, que é o
   * estado padrão de quem acabou de criar a instância.
   */
  clientToken: string | null
}

export async function getZapiCredentials(organizationId: string): Promise<ZapiCredentials> {
  const [integration] = await db
    .select({ id: integrations.id, config: integrations.config })
    .from(integrations)
    .where(and(
      eq(integrations.organizationId, organizationId),
      eq(integrations.type, ZAPI_INTEGRATION_TYPE),
      isNull(integrations.deletedAt)
    ))
    .limit(1)

  if (!integration) throw new Error('Integração Z-API não configurada.')

  const [secretRow] = await db
    .select({ secret: integrationSecrets.secret })
    .from(integrationSecrets)
    .where(eq(integrationSecrets.integrationId, integration.id))
    .limit(1)

  const config = (integration.config ?? {}) as { instance_id?: string }
  const secret = (secretRow?.secret ?? {}) as { instance_token?: string; client_token?: string }

  if (!config.instance_id || !secret.instance_token) {
    throw new Error('Credenciais da Z-API incompletas: falta o ID ou o token da instância.')
  }

  return {
    integrationId: integration.id,
    instanceId: config.instance_id,
    instanceToken: secret.instance_token,
    clientToken: secret.client_token || null,
  }
}

/** Existe integração Z-API configurada nesta organização? Não lança. */
export async function temZapiConfigurado(organizationId: string): Promise<boolean> {
  try {
    await getZapiCredentials(organizationId)
    return true
  } catch {
    return false
  }
}

function url(creds: ZapiCredentials, caminho: string): string {
  return `${BASE}/${creds.instanceId}/token/${creds.instanceToken}/${caminho}`
}

/**
 * Erro da Z-API em texto legível.
 *
 * Ela responde o motivo em `error` ou `message` conforme o endpoint, e às vezes
 * só devolve HTML de proxy. Sem isto, uma instância desconectada virava
 * "Falha ao enviar" genérico no `lead_activities.metadata` — o mesmo buraco que
 * a Evolution já teve (ver extractEvolutionError).
 */
function erroZapi(data: any, texto: string, status: number, fallback: string): string {
  if (typeof data?.error === 'string' && data.error) return data.error
  if (typeof data?.message === 'string' && data.message) return data.message
  if (texto && texto.length < 200 && !texto.trim().startsWith('<')) return texto
  return `${fallback} (HTTP ${status})`
}

async function chamar(
  creds: ZapiCredentials,
  caminho: string,
  init: { method?: string; body?: any } = {},
  fallbackErro = 'Falha na chamada à Z-API'
): Promise<any> {
  const res = await fetch(url(creds, caminho), {
    method: init.method || 'POST',
    headers: {
      'Content-Type': 'application/json',
      // Só vai quando existe: com a trava de segurança ligada na conta, a
      // ausência dele dá 403 em tudo; com a trava desligada, mandar um valor
      // vazio também é recusado. Então ou manda certo, ou não manda.
      ...(creds.clientToken ? { 'Client-Token': creds.clientToken } : {}),
    },
    ...(init.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
  })

  const texto = await res.text()
  let data: any = null
  try {
    data = texto ? JSON.parse(texto) : null
  } catch {
    data = null
  }

  if (!res.ok) throw new Error(erroZapi(data, texto, res.status, fallbackErro))
  return data
}

/**
 * Id de grupo ("120363428258502833-group"), e não telefone.
 *
 * A distinção importa porque tudo que mexe em telefone aqui — tirar máscara,
 * acrescentar o nono dígito, "corrigir" — destrói um id de grupo. Foi o que
 * aconteceu: o corretor de número tirou o "-group" do "Lead Magnet e CRM", o
 * registro ficou como "120363428258502833", e a partir daí toda mensagem que
 * chegava do grupo (com o sufixo) não casava com nada e era descartada.
 */
export function ehIdDeGrupo(valor: string): boolean {
  return /-group$/i.test(valor.trim()) || /[a-z]/i.test(valor)
}

/** Destinatário como a Z-API espera: telefone só com dígitos; grupo intacto. */
function destinatario(phone: string): string {
  if (ehIdDeGrupo(phone)) return phone.trim()
  return phone.replace(/\D/g, '')
}

/** Resultado de um envio: o que a Z-API devolveu e o número que funcionou. */
export interface EnvioZapi {
  data: any
  /** A forma do número que a Z-API aceitou — pode diferir da que foi pedida. */
  telefone: string
}

/**
 * Tenta enviar por cada forma do número até uma funcionar.
 *
 * O mesmo celular brasileiro existe com e sem o nono dígito, e qual das duas o
 * WhatsApp aceita depende da idade da conta — não dá pra saber de fora. O
 * endpoint `/phone-exists` da Z-API resolveria isso ANTES de enviar, mas nesta
 * instância ele responde "Whatsapp is not responding" mesmo com a sessão
 * conectada (testado duas vezes), então descobrir tentando é o caminho que sobra.
 *
 * Só tenta a segunda forma quando a primeira FALHA de verdade (a chamada
 * lançou), nunca quando ela deu 2xx — senão a pessoa receberia a mesma mensagem
 * duas vezes. Falhando todas, propaga o erro da primeira, que é o da forma
 * canônica e o mais informativo pra quem for investigar.
 */
async function comCorrecaoDeNumero(
  phone: string,
  enviar: (numero: string) => Promise<any>
): Promise<EnvioZapi> {
  // Grupo: uma tentativa só, com o id exatamente como está. Não existe "outra
  // forma" de um id de grupo, e devolver algo diferente em `telefone` faria
  // quem chamou gravar esse algo diferente no lugar do id verdadeiro.
  if (ehIdDeGrupo(phone)) {
    const id = phone.trim()
    return { data: await enviar(id), telefone: id }
  }

  const formas = telefoneVariantes(phone)
  const tentativas = formas.length > 0 ? formas : [destinatario(phone)]

  let primeiroErro: unknown = null
  for (const numero of tentativas) {
    try {
      const data = await enviar(numero)
      return { data, telefone: numero }
    } catch (err) {
      if (primeiroErro === null) primeiroErro = err
      console.warn('[zapi] envio falhou para ' + numero + '; tentando a outra forma do número', err)
    }
  }
  throw primeiroErro ?? new Error('Falha ao enviar pela Z-API')
}

/* ── Envio ────────────────────────────────────────────────────────────────── */

export async function sendZapiMessage(
  organizationId: string,
  phone: string,
  text: string
): Promise<EnvioZapi> {
  const creds = await getZapiCredentials(organizationId)
  return comCorrecaoDeNumero(phone, (numero) =>
    chamar(
      creds,
      'send-text',
      { body: { phone: destinatario(numero), message: text } },
      'Falha ao enviar mensagem pela Z-API'
    )
  )
}

/**
 * Mídia por link público — a Z-API baixa da URL que a gente manda.
 *
 * O CRM já hospeda o que o agente anexa no Blob da Vercel, então o link existe e
 * é estável. Documento é o único que leva a extensão no caminho da rota
 * (`send-document/pdf`): é dela que a Z-API tira o tipo do arquivo, então uma
 * extensão errada chega como arquivo corrompido do outro lado.
 */
export async function sendZapiMedia(
  organizationId: string,
  phone: string,
  mediaType: string,
  mediaUrl: string,
  caption?: string,
  fileName?: string
): Promise<EnvioZapi> {
  const creds = await getZapiCredentials(organizationId)

  // A Z-API aceita o webm que o navegador grava sem reclamar (200 OK), mas quem
  // recebe fica com um arquivo que não toca — ela não faz o remux que a Evolution
  // faz sozinha. Mesma conversão pra Ogg/Opus que os canais da Meta já usam (ver
  // src/lib/audioConvert.ts). Convertido uma vez aqui fora, antes do retry de
  // número — repetir a conversão a cada tentativa seria trabalho em dobro à toa.
  const effectiveMediaUrl = mediaType === 'audio' ? await convertAudioToVoiceNote(mediaUrl) : mediaUrl

  return comCorrecaoDeNumero(phone, (numero) => {
    const to = destinatario(numero)

    if (mediaType === 'image' || mediaType === 'sticker') {
      return chamar(creds, 'send-image', {
        body: { phone: to, image: mediaUrl, ...(caption ? { caption } : {}) },
      }, 'Falha ao enviar imagem pela Z-API')
    }

    if (mediaType === 'video') {
      return chamar(creds, 'send-video', {
        body: { phone: to, video: mediaUrl, ...(caption ? { caption } : {}) },
      }, 'Falha ao enviar vídeo pela Z-API')
    }

    if (mediaType === 'audio') {
      return chamar(creds, 'send-audio', {
        body: { phone: to, audio: effectiveMediaUrl },
      }, 'Falha ao enviar áudio pela Z-API')
    }

    const extensao = extensaoDe(fileName, mediaUrl)
    return chamar(creds, 'send-document/' + extensao, {
      body: { phone: to, document: mediaUrl, fileName: fileName || ('arquivo.' + extensao) },
    }, 'Falha ao enviar documento pela Z-API')
  })
}

/** Extensão do arquivo, do nome ou da URL. "bin" quando não dá pra saber. */
function extensaoDe(fileName?: string, mediaUrl?: string): string {
  const doNome = fileName?.split('.').pop()
  if (doNome && /^[a-z0-9]{1,5}$/i.test(doNome)) return doNome.toLowerCase()
  const semQuery = (mediaUrl || '').split('?')[0]
  const daUrl = semQuery.split('.').pop()
  if (daUrl && /^[a-z0-9]{1,5}$/i.test(daUrl)) return daUrl.toLowerCase()
  return 'bin'
}

/** Apaga "para todos" — `owner` diz se a mensagem era nossa. */
export async function deleteZapiMessage(
  organizationId: string,
  phone: string,
  messageId: string,
  owner = true
) {
  const creds = await getZapiCredentials(organizationId)
  const params = new URLSearchParams({
    messageId,
    phone: destinatario(phone),
    owner: String(owner),
  })
  return chamar(creds, `messages?${params}`, { method: 'DELETE' }, 'Falha ao apagar mensagem pela Z-API')
}

/* ── Instância ────────────────────────────────────────────────────────────── */

export interface ZapiStatus {
  connected: boolean
  session?: string
  smartphoneConnected?: boolean
  error?: string | null
}

export async function fetchZapiStatus(organizationId: string): Promise<ZapiStatus> {
  const creds = await getZapiCredentials(organizationId)
  const data = await chamar(creds, 'status', { method: 'GET' }, 'Falha ao consultar o status da Z-API')
  return {
    connected: !!data?.connected,
    session: data?.session,
    smartphoneConnected: data?.smartphoneConnected,
    error: data?.error ?? null,
  }
}

/** QR code em imagem (data URI base64) pra parear o número. */
export async function fetchZapiQrCode(organizationId: string): Promise<string | null> {
  const creds = await getZapiCredentials(organizationId)
  const data = await chamar(creds, 'qr-code/image', { method: 'GET' }, 'Falha ao gerar o QR code da Z-API')
  return data?.value ?? null
}

export async function disconnectZapi(organizationId: string) {
  const creds = await getZapiCredentials(organizationId)
  return chamar(creds, 'disconnect', { method: 'GET' }, 'Falha ao desconectar a Z-API')
}

/**
 * Aponta TODOS os webhooks da instância pra uma URL só.
 *
 * A Z-API tem um webhook por evento (recebida, status, conectado, desconectado) e
 * configurá-los na mão, um a um no painel dela, é onde alguém esquece justamente o
 * de mensagem recebida. Este endpoint grava os quatro de uma vez, e o nosso
 * handler separa os eventos pelo corpo.
 *
 * `notifySentByMe: true` é o que faz a mensagem que alguém do time manda DIRETO
 * do celular também chegar aqui. Sem essa flag, a conversa no CRM fica pela
 * metade — só o que o cliente escreve — e quem for atender depois não vê o que
 * já foi respondido, e responde de novo. A entrada já sabe tratar `fromMe`
 * (grava como mensagem de saída), então é só ligar.
 */
export async function updateZapiWebhooks(organizationId: string, webhookUrl: string) {
  const creds = await getZapiCredentials(organizationId)
  return chamar(creds, 'update-every-webhooks', {
    method: 'PUT',
    body: { value: webhookUrl, notifySentByMe: true },
  }, 'Falha ao configurar os webhooks da Z-API')
}

/* ── Conversas ────────────────────────────────────────────────────────────── */

export interface ZapiChat {
  phone: string
  name?: string | null
  unread?: string | number
  lastMessageTime?: string | number
  isGroup?: boolean
  archived?: string | boolean
}

/**
 * Lista de conversas da instância — SEM mensagens.
 *
 * A Z-API não tem endpoint de histórico e diz explicitamente que não guarda
 * mensagens ("são deletadas após envio"). Então isto aqui é o teto do que dá pra
 * importar de uma conta já em uso: quem é cada conversa, não o que foi dito nela.
 * O histórico do CRM começa no momento em que o webhook é ligado.
 */
export async function fetchZapiChats(
  organizationId: string,
  page = 1,
  pageSize = 50
): Promise<ZapiChat[]> {
  const creds = await getZapiCredentials(organizationId)
  const data = await chamar(
    creds,
    `chats?page=${page}&pageSize=${pageSize}`,
    { method: 'GET' },
    'Falha ao listar as conversas da Z-API'
  )
  return Array.isArray(data) ? data : (data?.chats ?? [])
}

/* ── Mídia ────────────────────────────────────────────────────────────────── */

/**
 * Baixa a mídia da Z-API e re-hospeda num link estável.
 *
 * A URL que chega no webhook é pública (ao contrário da Evolution, que manda um
 * *.enc criptografado), mas some depois de 30 dias — a própria documentação diz
 * isso. Guardar a URL original faria toda foto e todo áudio do chat morrerem em
 * silêncio um mês depois, que é o pior tipo de perda: a conversa continua lá,
 * só que furada.
 */
export async function rehospedarMidiaZapi(
  organizationId: string,
  mediaUrl: string,
  messageId: string
): Promise<{ url: string; mimetype?: string } | null> {
  try {
    const res = await fetch(mediaUrl)
    if (!res.ok) return null

    const mimetype = res.headers.get('content-type') || 'application/octet-stream'
    const buffer = Buffer.from(await res.arrayBuffer())

    const { put } = await import('@vercel/blob')
    const ext = mimetype.split('/')[1]?.split(';')[0] || 'bin'
    const blob = await put(`zapi-media/${organizationId}/${messageId}.${ext}`, buffer, {
      access: 'public',
      contentType: mimetype,
    })

    return { url: blob.url, mimetype }
  } catch (err) {
    console.error('[zapi] falha ao re-hospedar mídia', err)
    return null
  }
}

/** Foto de perfil do contato, re-hospedada — mesmo motivo de expiração acima. */
export async function rehospedarFotoPerfil(
  organizationId: string,
  fotoUrl: string,
  phone: string
): Promise<string | null> {
  try {
    const res = await fetch(fotoUrl)
    if (!res.ok) return null
    const mimetype = res.headers.get('content-type') || 'image/jpeg'
    const buffer = Buffer.from(await res.arrayBuffer())
    const { put } = await import('@vercel/blob')
    const ext = mimetype.split('/')[1]?.split(';')[0] || 'jpg'
    const blob = await put(`zapi-avatars/${organizationId}/${phone}-${Date.now()}.${ext}`, buffer, {
      access: 'public',
      contentType: mimetype,
    })
    return blob.url
  } catch (err) {
    console.error('[zapi] falha ao re-hospedar foto de perfil', err)
    return null
  }
}
