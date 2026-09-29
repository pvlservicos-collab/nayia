/**
 * Entrega um arquivo do disco respondendo a pedaço (Range) -- sem isso o áudio
 * e o vídeo não deixam arrastar a barra, e o Safari nem toca. Usado pelo
 * armazém (/api/midia) e pelo tocador de áudio (/api/media/audio).
 */
import { createReadStream } from 'node:fs'
import { stat } from 'node:fs/promises'
import { Readable } from 'node:stream'

export async function servirArquivo(arquivo: string, tipo: string, req: Request,
                                    cache = 'private, max-age=31536000, immutable'): Promise<Response> {
  let tamanho: number
  let modificado: Date
  try {
    const s = await stat(arquivo)
    if (!s.isFile()) return new Response('não encontrado', { status: 404 })
    tamanho = s.size
    modificado = s.mtime
  } catch {
    return new Response('não encontrado', { status: 404 })
  }

  const base: Record<string, string> = {
    'Content-Type': tipo,
    'Accept-Ranges': 'bytes',
    'Cache-Control': cache,
    'Last-Modified': modificado.toUTCString(),
    'X-Content-Type-Options': 'nosniff',
  }

  const pedaco = /^bytes=(\d*)-(\d*)$/.exec(req.headers.get('range') || '')
  if (pedaco && tamanho > 0 && (pedaco[1] !== '' || pedaco[2] !== '')) {
    let inicio = pedaco[1] === '' ? tamanho - Number(pedaco[2]) : Number(pedaco[1])
    let fim = pedaco[1] === '' || pedaco[2] === '' ? tamanho - 1 : Number(pedaco[2])
    inicio = Math.max(0, inicio)
    fim = Math.min(fim, tamanho - 1)
    if (inicio > fim || inicio >= tamanho) {
      return new Response(null, { status: 416, headers: { 'Content-Range': `bytes */${tamanho}` } })
    }
    const corpo = Readable.toWeb(createReadStream(arquivo, { start: inicio, end: fim })) as ReadableStream
    return new Response(corpo, {
      status: 206,
      headers: { ...base, 'Content-Range': `bytes ${inicio}-${fim}/${tamanho}`, 'Content-Length': String(fim - inicio + 1) },
    })
  }

  const corpo = Readable.toWeb(createReadStream(arquivo)) as ReadableStream
  return new Response(corpo, { status: 200, headers: { ...base, 'Content-Length': String(tamanho) } })
}
