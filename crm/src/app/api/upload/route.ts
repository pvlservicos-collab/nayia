/**
 * POST /api/upload -- o arquivo que alguém anexa no CRM (foto, vídeo, áudio,
 * documento, logo, avatar) vai para o armazém do próprio servidor (29/09/2026).
 *
 * Antes esta rota só emitia token para o navegador mandar direto ao Vercel
 * Blob -- que não existe neste servidor. Todo anexo quebrava aqui ("Vercel
 * Blob: No token found"), e foi assim que "mandar foto pelo CRM" nunca
 * funcionou. O corpo vem em multipart: o limite de 4,5MB era da Vercel, não
 * nosso.
 *
 * Campos: `arquivo` (o arquivo), `pasta` (avatars | org-logos | chat-media |
 * feature-screenshots), `id` (a quem pertence: lead, usuário...).
 * Devolve { url } -- o endereço relativo do armazém (/api/midia/...).
 */
import { NextRequest } from 'next/server'
import { randomUUID } from 'node:crypto'
import { auth } from '@/lib/auth'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { eq } from 'drizzle-orm'
import { guardarMidia } from '@/lib/armazem'

export const runtime = 'nodejs'

const IMAGENS = ['image/jpeg', 'image/png', 'image/webp', 'image/gif']
const FOLDER_LIMITS: Record<string, { maxSize: number; allowedContentTypes?: string[] }> = {
  avatars: { maxSize: 5 * 1024 * 1024, allowedContentTypes: IMAGENS },
  'org-logos': { maxSize: 5 * 1024 * 1024, allowedContentTypes: IMAGENS },
  // 64MB -- o maior que o WhatsApp aceita em documento pela Z-API; foto e vídeo
  // passam longe disso. Sem restrição de tipo (imagem, vídeo, áudio, documento).
  'chat-media': { maxSize: 64 * 1024 * 1024 },
  // Prints da tela Início -- global, só o superadmin sobe.
  'feature-screenshots': { maxSize: 5 * 1024 * 1024, allowedContentTypes: ['image/jpeg', 'image/png', 'image/webp'] },
}

export async function POST(req: NextRequest) {
  try {
    const session = await auth()
    if (!session?.user) return apiError(401, 'Não autenticado.')

    const form = await req.formData()
    const arquivo = form.get('arquivo')
    const pasta = String(form.get('pasta') || '')
    const dono = String(form.get('id') || 'geral')
    if (!(arquivo instanceof File)) return apiError(400, 'Faltou o arquivo.')

    const limites = FOLDER_LIMITS[pasta]
    if (!limites) return apiError(400, 'Pasta inválida. Use: avatars, org-logos, chat-media ou feature-screenshots')
    if (arquivo.size > limites.maxSize) {
      return apiError(413, `Arquivo grande demais (máximo ${Math.round(limites.maxSize / 1024 / 1024)}MB).`)
    }
    const tipo = (arquivo.type || 'application/octet-stream').split(';')[0].trim().toLowerCase()
    if (limites.allowedContentTypes && !limites.allowedContentTypes.includes(tipo)) {
      return apiError(400, 'Tipo de arquivo não aceito aqui.')
    }

    if (pasta === 'feature-screenshots') {
      const [profile] = await db.select({ isSuperadmin: profiles.isSuperadmin })
        .from(profiles).where(eq(profiles.id, session.user.id as string)).limit(1)
      if (!profile?.isSuperadmin) return apiError(403, 'Somente o superadmin pode trocar os prints da tela Início.')
    }

    const dados = Buffer.from(await arquivo.arrayBuffer())
    const url = await guardarMidia(`${pasta}/${dono}`, `${Date.now()}_${randomUUID().slice(0, 8)}`, dados, tipo, arquivo.name)
    return Response.json({ url, nome: arquivo.name, tipo, tamanho: arquivo.size })
  } catch (err: any) {
    console.error('[/api/upload]', err)
    return apiError(400, err?.message || 'Erro ao guardar o arquivo.')
  }
}
