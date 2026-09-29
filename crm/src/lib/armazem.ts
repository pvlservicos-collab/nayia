/**
 * O ARMAZÉM DE MÍDIA DO CRM (29/09/2026).
 *
 * Pedro: "veja também se os áudios estão indo certinho, tanto enviar quanto
 * escutar ..., fotos, e vídeos, e documentos".
 *
 * Não estavam. A mídia ia para o Vercel Blob, que não existe neste servidor
 * (não há BLOB_READ_WRITE_TOKEN). Medido em 29/09, nas últimas 72h: 193 mídias
 * recebidas e 147 fotos de perfil sem re-hospedar -- ficavam no link temporário
 * da Z-API, que some em ~30 dias --; a mídia que chega pelo número oficial se
 * perdia inteira; e mandar arquivo pelo CRM quebrava no upload.
 *
 * Agora tudo fica no disco do servidor (volume /docker/crm/midia, montado em
 * /data/midia) e sai por /api/midia/<caminho>:
 *   - para quem está logado no CRM;
 *   - para a Z-API e a Meta buscarem o que NÓS mandamos, por endereço assinado
 *     com validade (`enderecoParaFora`) -- elas não têm sessão.
 * O banco guarda o caminho RELATIVO (/api/midia/...), que não depende do domínio.
 */
import { createHash, createHmac, randomUUID, timingSafeEqual } from 'node:crypto'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'

export const PASTA_DO_ARMAZEM = process.env.ARMAZEM_DIR || '/data/midia'
export const PREFIXO_DA_MIDIA = '/api/midia/'

/** Abrem sem sessão: o logo aparece na tela de login. */
export const PASTAS_PUBLICAS = ['org-logos/']

const EXTENSAO_DO_TIPO: Record<string, string> = {
  'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
  'audio/ogg': 'ogg', 'audio/opus': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp3': 'mp3', 'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a', 'audio/aac': 'aac', 'audio/amr': 'amr', 'audio/webm': 'webm', 'audio/wav': 'wav',
  'video/mp4': 'mp4', 'video/3gpp': '3gp', 'video/quicktime': 'mov', 'video/webm': 'webm',
  'application/pdf': 'pdf', 'text/plain': 'txt', 'text/csv': 'csv', 'application/zip': 'zip',
  'application/msword': 'doc', 'application/vnd.ms-excel': 'xls', 'application/vnd.ms-powerpoint': 'ppt',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
}

const TIPO_DA_EXTENSAO: Record<string, string> = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif',
  ogg: 'audio/ogg', oga: 'audio/ogg', opus: 'audio/ogg', mp3: 'audio/mpeg', m4a: 'audio/mp4', aac: 'audio/aac',
  amr: 'audio/amr', wav: 'audio/wav', weba: 'audio/webm',
  mp4: 'video/mp4', '3gp': 'video/3gpp', mov: 'video/quicktime', webm: 'video/webm',
  pdf: 'application/pdf', txt: 'text/plain; charset=utf-8', csv: 'text/csv; charset=utf-8', zip: 'application/zip',
  doc: 'application/msword', xls: 'application/vnd.ms-excel', ppt: 'application/vnd.ms-powerpoint',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
}

/** "image/jpeg; x" -> "jpg"; sem tipo conhecido, tenta a extensão do nome. */
export function extensaoDoTipo(tipo: string | null | undefined, nome?: string | null): string {
  const limpo = String(tipo || '').split(';')[0].trim().toLowerCase()
  if (EXTENSAO_DO_TIPO[limpo]) return EXTENSAO_DO_TIPO[limpo]
  const doNome = String(nome || '').split('?')[0].split('.').pop()?.toLowerCase()
  if (doNome && /^[a-z0-9]{1,5}$/.test(doNome) && doNome !== String(nome).toLowerCase()) return doNome
  const sub = limpo.split('/')[1]
  return sub && /^[a-z0-9]{1,5}$/.test(sub) ? sub : 'bin'
}

export function tipoDaExtensao(caminho: string): string {
  const ext = caminho.split('.').pop()?.toLowerCase() || ''
  return TIPO_DA_EXTENSAO[ext] || 'application/octet-stream'
}

/** Pedaço de nome de arquivo sem nada que escape da pasta. */
function limpar(s: string, max = 80): string {
  return String(s || '').replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '').slice(0, max) || 'arquivo'
}

/** "zapi-media/org/abc.ogg" -- só letras, números, - _ . e /, sem "..", sem barra no começo. */
export function caminhoSeguro(rel: string): string | null {
  const r = String(rel || '').replace(/\\/g, '/').replace(/^\/+/, '')
  if (!r || r.length > 300 || !/^[A-Za-z0-9._\-/]+$/.test(r)) return null
  if (r.split('/').some((p) => p === '' || p === '.' || p === '..')) return null
  return r
}

/**
 * Guarda os bytes e devolve o endereço relativo (/api/midia/pasta/nome.ext).
 * Grava num temporário e renomeia: quem lê nunca pega o arquivo pela metade.
 */
export async function guardarMidia(pasta: string, nome: string, dados: Buffer | Uint8Array, tipo?: string | null,
                                   nomeOriginal?: string | null): Promise<string> {
  const pastaLimpa = pasta.split('/').map((p) => limpar(p, 60)).join('/')
  const rel = caminhoSeguro(`${pastaLimpa}/${limpar(nome)}.${extensaoDoTipo(tipo, nomeOriginal)}`)
  if (!rel) throw new Error('caminho de mídia inválido')
  const destino = join(PASTA_DO_ARMAZEM, rel)
  await mkdir(dirname(destino), { recursive: true })
  const temporario = `${destino}.${randomUUID()}.parcial`
  await writeFile(temporario, dados)
  await rename(temporario, destino)
  return PREFIXO_DA_MIDIA + rel
}

/** Baixa um endereço e guarda. null quando a origem não responde (o link venceu, por exemplo). */
export async function guardarDoEndereco(pasta: string, nome: string, url: string,
                                        cabecalhos?: Record<string, string>): Promise<{ url: string; mimetype: string } | null> {
  try {
    const res = await fetch(url, { headers: cabecalhos, signal: AbortSignal.timeout(60000) })
    if (!res.ok) return null
    const mimetype = (res.headers.get('content-type') || 'application/octet-stream').split(';')[0].trim()
    const dados = Buffer.from(await res.arrayBuffer())
    if (!dados.length) return null
    return { url: await guardarMidia(pasta, nome, dados, mimetype, url), mimetype }
  } catch (err) {
    console.error('[armazem] não consegui baixar e guardar', pasta, nome, (err as Error)?.message)
    return null
  }
}

/** O caminho dentro do armazém, se o endereço for nosso (relativo ou absoluto, assinado ou não). */
export function relativoDoArmazem(url: string | null | undefined): string | null {
  const u = String(url || '')
  const i = u.indexOf(PREFIXO_DA_MIDIA)
  if (i < 0) return null
  if (i > 0) {
    // absoluto: só vale o nosso próprio domínio
    try {
      const base = new URL(baseDoApp() || 'http://x')
      const alvo = new URL(u)
      if (alvo.host !== base.host) return null
    } catch { return null }
  }
  return caminhoSeguro(decodeURIComponent(u.slice(i + PREFIXO_DA_MIDIA.length).split('?')[0]))
}

export function ehDoArmazem(url: string | null | undefined): boolean {
  return relativoDoArmazem(url) !== null
}

/** Os bytes de uma mídia -- do disco, se for nossa; senão, da internet. */
export async function lerMidia(url: string): Promise<{ dados: Buffer; tipo: string } | null> {
  const rel = relativoDoArmazem(url)
  if (rel) {
    try {
      return { dados: await readFile(join(PASTA_DO_ARMAZEM, rel)), tipo: tipoDaExtensao(rel) }
    } catch { return null }
  }
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(60000) })
    if (!res.ok) return null
    return { dados: Buffer.from(await res.arrayBuffer()), tipo: (res.headers.get('content-type') || '').split(';')[0].trim() }
  } catch { return null }
}

export function baseDoApp(): string {
  return String(process.env.NEXT_PUBLIC_APP_URL || process.env.NEXTAUTH_URL || process.env.AUTH_URL || '').replace(/\/+$/, '')
}

function chave(): Buffer {
  const segredo = process.env.AUTH_SECRET || process.env.NEXTAUTH_SECRET
  if (!segredo) throw new Error('AUTH_SECRET ausente: não dá para assinar endereço de mídia')
  return createHash('sha256').update('armazem-de-midia:' + segredo).digest()
}

function assinatura(rel: string, exp: number): string {
  return createHmac('sha256', chave()).update(`${rel}|${exp}`).digest('base64url')
}

export function assinaturaValida(rel: string, exp: number, sig: string): boolean {
  if (!Number.isFinite(exp) || exp * 1000 < Date.now() || !sig) return false
  try {
    const certo = Buffer.from(assinatura(rel, exp))
    const veio = Buffer.from(sig)
    return certo.length === veio.length && timingSafeEqual(certo, veio)
  } catch { return false }
}

/**
 * O endereço que a Z-API / a Meta usam para baixar o que mandamos: absoluto e
 * assinado. Endereço de fora (site, Z-API) passa como está.
 */
export function enderecoParaFora(url: string, validadeSegundos = 7 * 24 * 3600): string {
  const rel = relativoDoArmazem(url)
  if (!rel) return url
  const base = baseDoApp()
  if (!base) throw new Error('NEXT_PUBLIC_APP_URL ausente: a Z-API não teria de onde baixar a mídia')
  const exp = Math.floor(Date.now() / 1000) + validadeSegundos
  return `${base}${PREFIXO_DA_MIDIA}${rel}?exp=${exp}&sig=${assinatura(rel, exp)}`
}
