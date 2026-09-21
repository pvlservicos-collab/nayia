/**
 * POST /api/upload
 * Emite tokens de upload direto-pro-Blob (fluxo `handleUpload` do @vercel/blob/client).
 *
 * O arquivo NÃO passa mais por essa function — o navegador envia os bytes direto pro
 * Vercel Blob usando o token que essa rota autoriza. Isso existe porque Vercel Functions
 * têm um limite rígido de 4.5MB no corpo da requisição (plataforma, não configurável):
 * qualquer vídeo ou foto de celular um pouco maior era rejeitado (413) antes mesmo do
 * nosso código rodar. Ver src/lib/blobClient.ts para o lado cliente e o motivo completo.
 */
import { NextRequest } from 'next/server'
import { handleUpload, type HandleUploadBody } from '@vercel/blob/client'
import { auth } from '@/lib/auth'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { eq } from 'drizzle-orm'

const FOLDER_LIMITS: Record<string, { maxSize: number; allowedContentTypes?: string[] }> = {
  avatars: { maxSize: 5 * 1024 * 1024, allowedContentTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] },
  'org-logos': { maxSize: 5 * 1024 * 1024, allowedContentTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] },
  // 16MB — limite de mídia do WhatsApp; sem restrição de tipo (imagem, vídeo, áudio, documento)
  'chat-media': { maxSize: 16 * 1024 * 1024 },
  // Prints da tela Início — global, só o superadmin sobe (checado abaixo, além do
  // POST /api/platform/feature-screenshots exigir superadmin pra registrar a URL).
  'feature-screenshots': { maxSize: 5 * 1024 * 1024, allowedContentTypes: ['image/jpeg', 'image/png', 'image/webp'] },
}

export async function POST(req: NextRequest) {
  try {
    const body = (await req.json()) as HandleUploadBody

    const jsonResponse = await handleUpload({
      body,
      request: req,
      onBeforeGenerateToken: async (pathname) => {
        // Só o pedido de token (feito pelo navegador do usuário) tem cookie de sessão —
        // o callback abaixo (onUploadCompleted) é o servidor da própria Vercel chamando
        // de volta depois do upload, sem sessão de usuário; exigir auth() ali quebraria
        // esse callback sempre. A autenticidade da chamada da Vercel já é validada pela
        // assinatura interna do handleUpload, não precisa de checagem extra aqui.
        const session = await auth()
        if (!session?.user) throw new Error('Não autenticado.')

        const folder = pathname.split('/')[0]
        const limits = FOLDER_LIMITS[folder]
        if (!limits) throw new Error('Pasta inválida. Use: avatars, org-logos, chat-media ou feature-screenshots')

        if (folder === 'feature-screenshots') {
          const [profile] = await db.select({ isSuperadmin: profiles.isSuperadmin })
            .from(profiles).where(eq(profiles.id, session.user.id as string)).limit(1)
          if (!profile?.isSuperadmin) throw new Error('Somente o superadmin pode trocar os prints da tela Início.')
        }

        return {
          allowedContentTypes: limits.allowedContentTypes,
          maximumSizeInBytes: limits.maxSize,
          addRandomSuffix: true,
        }
      },
      onUploadCompleted: async () => {
        // Nada a fazer — o cliente já recebe a URL final na resposta do upload().
        // (Em dev local, a Vercel não consegue chamar esse callback de volta pro
        // localhost; isso é esperado e não afeta o upload em si.)
      },
    })

    return Response.json(jsonResponse)
  } catch (err: any) {
    console.error('[/api/upload]', err)
    return apiError(400, err.message || 'Erro ao autorizar upload.')
  }
}
