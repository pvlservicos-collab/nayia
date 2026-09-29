/**
 * GET /api/media/audio?url=<endereço do áudio>
 *
 * TOCA O ÁUDIO EM QUALQUER NAVEGADOR (Tel, 26/09/2026: "quando clico em
 * reproduzir audio no crm não reproduz").
 *
 * A Z-API entrega nota de voz como `audio/ogg; codecs=opus` -- medido nos
 * áudios reais do CRM. Chrome e Firefox tocam; o **Safari não toca ogg**, nem
 * no Mac nem no iPhone. Como o tocador engolia o erro, o clique não fazia
 * nada e não aparecia aviso nenhum.
 *
 * Esta rota busca o áudio original e devolve **m4a/aac**, que toca em todos.
 * Se o original já for um formato universal (mp3, m4a, wav), ela repassa sem
 * converter -- não há por que gastar CPU.
 *
 * 29/09/2026: o áudio agora mora no armazém do CRM (/api/midia/...), e a
 * conversão fica guardada lá também (pasta _audio, que o /api/midia não
 * entrega) -- no /tmp do container ela sumia a cada publicação, e cada áudio
 * voltava a passar pelo ffmpeg. E a rota pede login: com o áudio atrás de
 * sessão, ela não pode virar a porta dos fundos dele.
 *
 * NÃO É UM PROXY ABERTO. Só busca do armazém ou de uma lista de domínios
 * conhecidos; sem isso, qualquer um poderia usar o CRM para buscar qualquer
 * endereço da internet (e da rede interna) em nome do servidor.
 */
import { spawn } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import ffmpegPath from 'ffmpeg-static'
import { NextRequest } from 'next/server'
import { auth } from '@/lib/auth'
import { PASTA_DO_ARMAZEM, relativoDoArmazem, tipoDaExtensao } from '@/lib/armazem'
import { servirArquivo } from '@/lib/servirArquivo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** De onde aceitamos buscar áudio. Sufixo de domínio, comparado no fim. */
const DOMINIOS_PERMITIDOS = [
  'backblazeb2.com',        // armazenamento temporário da Z-API (áudio de antes de 29/09)
  'imobeasy.com',
  'imobeasy.online',
  'lookaside.fbsbx.com',    // mídia da Meta (WhatsApp Cloud / Instagram)
  'cdn.fbsbx.com',
  'public.blob.vercel-storage.com',
  'uazapi.com',
]

/** Formatos que todo navegador toca -- estes passam direto. */
const JA_TOCA = ['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/x-m4a']

const PASTA = join(PASTA_DO_ARMAZEM, '_audio')
const CACHE = 'private, max-age=31536000, immutable'

function permitido(u: URL): boolean {
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return false
  const host = u.hostname.toLowerCase()
  return DOMINIOS_PERMITIDOS.some((d) => host === d || host.endsWith('.' + d))
}

function ffmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) return reject(new Error('ffmpeg não disponível'))
    const p = spawn(ffmpegPath, args)
    let err = ''
    p.stderr.on('data', (c) => { err += c.toString() })
    p.on('error', reject)
    p.on('close', (code) =>
      code === 0 ? resolve() : reject(new Error(`ffmpeg ${code}: ${err.slice(-400)}`)))
  })
}

export async function GET(req: NextRequest) {
  const sessao = await auth()
  if (!sessao?.user) return new Response('não autenticado', { status: 401 })

  const bruto = req.nextUrl.searchParams.get('url')
  if (!bruto) return new Response('falta ?url=', { status: 400 })

  const nosso = relativoDoArmazem(bruto)
  let alvo: URL | null = null
  if (!nosso) {
    try {
      alvo = new URL(bruto)
    } catch {
      return new Response('endereço inválido', { status: 400 })
    }
    if (!permitido(alvo)) return new Response('domínio não permitido', { status: 403 })
  }

  const marca = createHash('sha1').update(nosso ? 'armazem:' + nosso : alvo!.toString()).digest('hex')
  const convertido = join(PASTA, marca + '.m4a')

  try {
    if (!existsSync(PASTA)) await mkdir(PASTA, { recursive: true })

    // já convertido antes
    if (existsSync(convertido)) return servirArquivo(convertido, 'audio/mp4', req, CACHE)

    let tipo: string
    let bytes: Buffer
    if (nosso) {
      tipo = tipoDaExtensao(nosso).split(';')[0]
      // formato que todo navegador toca: entrega o próprio arquivo, com pedaço
      if (JA_TOCA.includes(tipo)) return servirArquivo(join(PASTA_DO_ARMAZEM, nosso), tipo, req, CACHE)
      try {
        bytes = await readFile(join(PASTA_DO_ARMAZEM, nosso))
      } catch {
        return new Response('áudio não encontrado', { status: 404 })
      }
    } else {
      const origem = await fetch(alvo!.toString(), { signal: AbortSignal.timeout(30000) })
      if (!origem.ok) {
        // 403/404 do Backblaze = o link temporário da Z-API venceu
        return new Response(`origem respondeu ${origem.status}`, { status: 502 })
      }
      tipo = (origem.headers.get('content-type') || '').split(';')[0].trim().toLowerCase()
      bytes = Buffer.from(await origem.arrayBuffer())
      if (JA_TOCA.includes(tipo)) {
        return new Response(new Uint8Array(bytes), { headers: { 'Content-Type': tipo, 'Cache-Control': CACHE } })
      }
    }

    const entrada = join(PASTA, marca + '.orig')
    const saida = join(PASTA, marca + '.parcial.m4a')
    await writeFile(entrada, bytes)
    try {
      // -vn: só áudio. 64k mono basta pra voz e deixa o arquivo pequeno.
      await ffmpeg(['-y', '-i', entrada, '-vn', '-c:a', 'aac', '-b:a', '64k', '-ac', '1',
                    '-movflags', 'faststart', saida])
      await rename(saida, convertido)
    } finally {
      await unlink(entrada).catch(() => {})
      await unlink(saida).catch(() => {})
    }
    return servirArquivo(convertido, 'audio/mp4', req, CACHE)
  } catch (e: any) {
    return new Response(`falha ao preparar o áudio: ${e?.message ?? e}`, { status: 500 })
  }
}
