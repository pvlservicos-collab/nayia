/**
 * Prints das funções mostrados na tela Início (Chat, Pipeline, Funis, Logística,
 * Financeiro, Métricas, Configurações). Globais — não pertencem a nenhuma
 * organização, são a mesma imagem pra qualquer tenant. Só o superadmin da
 * plataforma pode trocar (POST); qualquer usuário autenticado pode ler (GET).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { featureScreenshots } from '@/lib/schema'
import { eq } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const rows = await db.select({ featureKey: featureScreenshots.featureKey, imageUrl: featureScreenshots.imageUrl })
      .from(featureScreenshots)

    const map: Record<string, string> = {}
    for (const row of rows) map[row.featureKey] = row.imageUrl

    return Response.json(map)
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.isSuperAdmin) return apiError(403, 'Somente o superadmin pode trocar os prints.')

    const body = await req.json().catch(() => ({}))
    const missing = validateRequired(body ?? {}, ['feature_key', 'image_url'])
    if (missing) return apiError(400, missing)

    const { feature_key, image_url } = body

    const existing = await db.select({ id: featureScreenshots.id }).from(featureScreenshots)
      .where(eq(featureScreenshots.featureKey, feature_key)).limit(1)

    if (existing.length > 0) {
      await db.update(featureScreenshots).set({ imageUrl: image_url, updatedAt: new Date() })
        .where(eq(featureScreenshots.featureKey, feature_key))
    } else {
      await db.insert(featureScreenshots).values({ featureKey: feature_key, imageUrl: image_url })
    }

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
