/**
 * COPIA PARA O ARMAZÉM A MÍDIA QUE FICOU SÓ NO LINK TEMPORÁRIO (29/09/2026).
 *
 * Até 29/09 a mídia da Z-API ia para o Vercel Blob, que não existe neste
 * servidor; quando falhava, o CRM guardava o link do Backblaze da Z-API, que
 * some em ~30 dias. Em 29/09 eram 262 mídias assim, todas de 25/09 em diante --
 * ainda a tempo. Este script baixa cada uma para o armazém (src/lib/armazem.ts)
 * e troca o `media_url` pelo endereço /api/midia/...; o link antigo fica em
 * `media_url_original`. Link que já venceu fica como está (e é contado).
 *
 * Roda DENTRO do container, onde estão o banco e o volume:
 *   docker cp scripts/rehospedar-midia-antiga.mjs crm-imobeasy:/app/scripts/
 *   docker exec crm-imobeasy node scripts/rehospedar-midia-antiga.mjs            (só conta)
 *   docker exec crm-imobeasy node scripts/rehospedar-midia-antiga.mjs --gravar
 */
import pg from 'pg'
import { mkdir, rename, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { randomUUID } from 'node:crypto'

const PASTA = process.env.ARMAZEM_DIR || '/data/midia'
const GRAVAR = process.argv.includes('--gravar')
const EXT = {
  'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif',
  'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/mp4': 'm4a', 'audio/aac': 'aac', 'audio/amr': 'amr',
  'video/mp4': 'mp4', 'video/3gpp': '3gp', 'application/pdf': 'pdf',
}
const limpar = (s) => String(s || '').replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 80) || 'arquivo'

function extensao(tipo, url) {
  const t = String(tipo || '').split(';')[0].trim().toLowerCase()
  if (EXT[t]) return EXT[t]
  const daUrl = String(url || '').split('?')[0].split('.').pop()?.toLowerCase()
  if (daUrl && /^[a-z0-9]{1,5}$/.test(daUrl)) return daUrl
  const sub = t.split('/')[1]
  return sub && /^[a-z0-9]{1,5}$/.test(sub) ? sub : 'bin'
}

const db = new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 2 })
const { rows } = await db.query(`
  SELECT id, organization_id, metadata
    FROM lead_activities
   WHERE metadata->>'media_url' ~ '^https://[^/]*backblazeb2\\.com/'
   ORDER BY created_at DESC`)
console.log(`${rows.length} mídias no link temporário${GRAVAR ? '' : ' (só contando; --gravar para copiar)'}`)

let copiadas = 0, vencidas = 0, falhas = 0
for (const a of rows) {
  const m = a.metadata || {}
  const url = m.media_url
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(60000) })
    if (!res.ok) { vencidas++; continue }
    if (!GRAVAR) { copiadas++; await res.arrayBuffer(); continue }
    const tipo = (res.headers.get('content-type') || m.media_mimetype || '').split(';')[0].trim()
    const dados = Buffer.from(await res.arrayBuffer())
    if (!dados.length) { vencidas++; continue }
    const rel = `zapi-media/${limpar(a.organization_id)}/${limpar(m.zapi_message_id || a.id)}.${extensao(tipo || m.media_mimetype, url)}`
    const destino = join(PASTA, rel)
    await mkdir(dirname(destino), { recursive: true })
    const temporario = `${destino}.${randomUUID()}.parcial`
    await writeFile(temporario, dados)
    await rename(temporario, destino)
    await db.query(`
      UPDATE lead_activities
         SET metadata = metadata || jsonb_build_object('media_url', $2::text, 'media_url_original', $3::text,
                                                       'media_mimetype', coalesce(metadata->>'media_mimetype', $4::text)),
             updated_at = now()
       WHERE id = $1 AND metadata->>'media_url' = $3`,
      [a.id, '/api/midia/' + rel, url, tipo || null])
    copiadas++
  } catch (e) {
    falhas++
    console.error('falhou', a.id, e?.message)
  }
  await new Promise((r) => setTimeout(r, 150))   // devagar: o servidor é dividido com a Nay
}
console.log(`${GRAVAR ? 'copiadas' : 'ainda abrem'}: ${copiadas} | link vencido: ${vencidas} | falhas: ${falhas}`)
await db.end()
