import { NextRequest } from 'next/server'
import { jwtVerify } from 'jose'
import { eq, and } from 'drizzle-orm'
import { db } from './db'
import { apiTokens, organizationMembers, profiles } from './schema'
import { auth } from './auth'

/**
 * Painel /admin (plataforma inteira, todas as organizações) — gate por
 * profiles.isSuperadmin, NUNCA por nome de papel de organização. Um papel
 * chamado "Founder"/"Admin" é só um rótulo dentro da própria org e qualquer
 * organização poderia criar um papel com esse mesmo nome; isSuperadmin é a
 * única flag que não pode ser auto-concedida por um tenant.
 */
export async function requireSuperadmin(): Promise<{ userId: string }> {
  const session = await auth()
  if (!session?.user?.id) throw { status: 401, message: 'Não autenticado.' }
  const [profile] = await db.select({ isSuperadmin: profiles.isSuperadmin })
    .from(profiles).where(eq(profiles.id, session.user.id)).limit(1)
  if (!profile?.isSuperadmin) throw { status: 403, message: 'Acesso restrito ao painel administrativo.' }
  return { userId: session.user.id }
}

interface AuthResult {
  organizationId: string
  memberId: string | null
  userId: string | null
  roleId: string | null
  isSuperAdmin?: boolean
}

async function hashToken(token: string): Promise<string> {
  const encoder = new TextEncoder()
  const data = encoder.encode(token)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('')
}

async function getMemberByUserId(userId: string) {
  const [member] = await db
    .select({
      id: organizationMembers.id,
      organizationId: organizationMembers.organizationId,
      roleId: organizationMembers.roleId,
      isSuperadmin: profiles.isSuperadmin,
    })
    .from(organizationMembers)
    .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
    .where(and(eq(organizationMembers.userId, userId), eq(organizationMembers.status, 'active')))
    .limit(1)
  return member
}

export async function authenticateRequest(req: NextRequest): Promise<AuthResult> {
  const authHeader = req.headers.get('authorization')

  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.replace('Bearer ', '').trim()
    if (!token) throw { status: 401, message: 'Token vazio.' }

    if (token.startsWith('atl_')) {
      const tokenHash = await hashToken(token)
      const [apiToken] = await db
        .select({ organizationId: apiTokens.organizationId })
        .from(apiTokens)
        .where(and(eq(apiTokens.tokenHash, tokenHash), eq(apiTokens.isActive, true)))
        .limit(1)
      if (!apiToken) throw { status: 401, message: 'Token de API inválido ou revogado.' }
      db.update(apiTokens).set({ lastUsedAt: new Date() }).where(eq(apiTokens.tokenHash, tokenHash)).catch(console.error)
      return { organizationId: apiToken.organizationId, memberId: null, userId: null, roleId: null }
    }

    try {
      const secret = new TextEncoder().encode(process.env.AUTH_SECRET)
      const { payload } = await jwtVerify(token, secret)
      const userId = payload.id as string
      if (!userId) throw new Error('JWT sem user id')
      const member = await getMemberByUserId(userId)
      if (!member) throw { status: 403, message: 'Usuário não associado a nenhuma organização ativa.' }
      return {
        organizationId: member.organizationId,
        memberId: member.id,
        userId,
        roleId: member.roleId,
        isSuperAdmin: member.isSuperadmin || false,
      }
    } catch (err: any) {
      if (err.status) throw err
      throw { status: 401, message: 'JWT inválido ou expirado.' }
    }
  }

  // Fallback: NextAuth cookie session (requisições do browser same-origin)
  const session = await auth()
  if (session?.user?.id) {
    const userId = session.user.id
    const member = await getMemberByUserId(userId)
    if (member) {
      return {
        organizationId: member.organizationId,
        memberId: member.id,
        userId,
        roleId: member.roleId,
        isSuperAdmin: member.isSuperadmin || false,
      }
    }
  }

  throw { status: 401, message: 'Token de autenticação não fornecido. Use Authorization: Bearer <token>' }
}

export function apiError(status: number, message: string) {
  return Response.json({ error: message }, { status })
}

export function validateRequired(body: Record<string, any>, fields: string[]): string | null {
  for (const field of fields) {
    if (body[field] === undefined || body[field] === null || body[field] === '') {
      return `Campo obrigatório ausente: ${field}`
    }
  }
  return null
}

export function validateSource(source: string): string | null {
  if (!source || typeof source !== 'string' || source.trim() === '') {
    return `Valor inválido para source: "${source}". Deve ser uma string não vazia.`
  }
  return null
}
