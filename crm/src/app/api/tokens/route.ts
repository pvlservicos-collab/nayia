import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { apiTokens } from '@/lib/schema'
import { eq, and, desc } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const data = await db.select({
      id: apiTokens.id,
      name: apiTokens.name,
      isActive: apiTokens.isActive,
      lastUsedAt: apiTokens.lastUsedAt,
      createdAt: apiTokens.createdAt,
    }).from(apiTokens)
      .where(and(eq(apiTokens.organizationId, auth.organizationId), eq(apiTokens.isActive, true)))
      .orderBy(desc(apiTokens.createdAt))
    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

/**
 * Gera um token `atl_` e devolve o SHA-256 dele. O banco guarda só o hash — o
 * valor em claro existe uma única vez, na resposta desta rota.
 */
function generateToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, '0')).join('')
  return `atl_${hex}`
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const body = await req.json()
    if (!body.name) return apiError(400, 'name é obrigatório.')

    // Duas formas de criar, e é de propósito:
    //  - com `token_hash`: o cliente gerou e hasheou (é o que a tela de
    //    Configurações → Organização já faz; o valor em claro nunca sai de lá);
    //  - sem: o servidor gera e devolve `token` UMA vez nesta resposta.
    // A segunda existe pra quem só quer uma chave sem reimplementar SHA-256 —
    // a tela /leads usa ela.
    let plaintext: string | null = null
    let tokenHash: string
    if (body.token_hash) {
      tokenHash = body.token_hash
    } else {
      plaintext = generateToken()
      tokenHash = await sha256Hex(plaintext)
    }

    const [token] = await db.insert(apiTokens).values({
      organizationId: auth.organizationId,
      name: body.name,
      tokenHash,
    }).returning({ id: apiTokens.id, name: apiTokens.name, createdAt: apiTokens.createdAt })

    return Response.json({ data: { ...token, token: plaintext } }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function DELETE(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const id = req.nextUrl.searchParams.get('id')
    if (!id) return apiError(400, 'id é obrigatório.')
    await db.update(apiTokens).set({ isActive: false })
      .where(and(eq(apiTokens.id, id), eq(apiTokens.organizationId, auth.organizationId)))
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
