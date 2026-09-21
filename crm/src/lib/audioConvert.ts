/**
 * Converte áudio gravado no navegador (webm/opus ou mp4/aac) pra Ogg com codec Opus
 * puro — o único formato que toca como nota de voz de verdade (bolha com onda sonora,
 * tocável) em vez de aparecer como anexo genérico ou simplesmente não tocar. O
 * navegador grava em audio/webm (Chrome/Edge) ou audio/mp4 (Safari); nenhum WhatsApp
 * aceita esses formatos como voice note.
 *
 * Chamado pelos canais da Meta (WhatsApp Cloud API e Instagram Direct: a Meta rejeita
 * o webm de cara com "Unsupported MIME type", erro 131053 documentado) e pela Z-API
 * (ela aceita o webm sem reclamar, mas manda pro destinatário um arquivo que não
 * toca — sem erro nenhum pro nosso lado, só reclamação de quem recebeu). A Evolution
 * API (WhatsApp Nº2) é a única que já faz essa conversão no próprio servidor dela.
 */
import { spawn } from 'node:child_process'
import { writeFile, readFile, unlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import ffmpegPath from 'ffmpeg-static'
import { put } from '@vercel/blob'

function runFfmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    if (!ffmpegPath) {
      reject(new Error('ffmpeg não disponível neste ambiente.'))
      return
    }
    const proc = spawn(ffmpegPath, args)
    let stderr = ''
    proc.stderr.on('data', (chunk) => { stderr += chunk.toString() })
    proc.on('error', reject)
    proc.on('close', (code) => {
      if (code === 0) resolve()
      else reject(new Error(`ffmpeg falhou (código ${code}): ${stderr.slice(-500)}`))
    })
  })
}

export async function convertAudioToVoiceNote(sourceUrl: string): Promise<string> {
  const res = await fetch(sourceUrl)
  if (!res.ok) throw new Error(`Falha ao baixar áudio original (HTTP ${res.status})`)
  const inputBuffer = Buffer.from(await res.arrayBuffer())

  const tmpId = `${Date.now()}-${Math.random().toString(36).slice(2)}`
  const inputPath = join(tmpdir(), `audio-in-${tmpId}`)
  const outputPath = join(tmpdir(), `audio-out-${tmpId}.ogg`)

  await writeFile(inputPath, inputBuffer)

  try {
    // -c:a libopus sempre recodifica (não usa -c copy): garante saída Ogg/Opus válida
    // não importa o container/codec de origem (webm+opus do Chrome, mp4+aac do Safari).
    await runFfmpeg([
      '-y',
      '-i', inputPath,
      '-c:a', 'libopus',
      '-b:a', '32k',
      '-ar', '48000',
      '-ac', '1',
      '-f', 'ogg',
      outputPath,
    ])

    const outputBuffer = await readFile(outputPath)
    const blob = await put(`chat-media/audio-meta/${tmpId}.ogg`, outputBuffer, {
      access: 'public',
      contentType: 'audio/ogg',
    })
    return blob.url
  } finally {
    await Promise.allSettled([unlink(inputPath), unlink(outputPath)])
  }
}
