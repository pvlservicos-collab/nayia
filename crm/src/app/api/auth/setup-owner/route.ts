import { NextRequest } from 'next/server'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { users, profiles, organizationMembers, organizationRoles, setupTokens, organizations } from '@/lib/schema'
import { eq, and, gt, sql } from 'drizzle-orm'
import bcrypt from 'bcryptjs'

// Limite fixo de contas com acesso total (painel /admin). Só muda se o próprio
// founder pedir explicitamente pra levantar esse número.
const MAX_FOUNDERS = 2

// GET /api/auth/setup-owner?token=... — usado por /ativar-conta pra mostrar o nome
// do workspace antes do cliente preencher o formulário, sem expor mais nada do token.
export async function GET(req: NextRequest) {
  try {
    const token = req.nextUrl.searchParams.get('token')
    if (!token) return apiError(400, 'Token obrigatório.')

    const [row] = await db
      .select({
        usedAt: setupTokens.usedAt,
        expiresAt: setupTokens.expiresAt,
        organizationName: organizations.name,
      })
      .from(setupTokens)
      .innerJoin(organizations, eq(organizations.id, setupTokens.organizationId))
      .where(eq(setupTokens.token, token))
      .limit(1)

    if (!row || row.usedAt || row.expiresAt < new Date()) {
      return Response.json({ valid: false })
    }

    return Response.json({ valid: true, organization_name: row.organizationName })
  } catch (err: any) {
    return apiError(500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json()
    const { setup_token, full_name, email, password } = body

    if (!setup_token || !full_name || !email || !password) {
      return apiError(400, 'Campos obrigatórios: setup_token, full_name, email, password')
    }

    if (password.length < 8) return apiError(400, 'Senha deve ter pelo menos 8 caracteres.')

    // Validar token
    const [token] = await db.select().from(setupTokens)
      .where(and(eq(setupTokens.token, setup_token), gt(setupTokens.expiresAt, new Date())))
      .limit(1)

    if (!token || token.usedAt) return apiError(400, 'Token inválido ou expirado.')

    const isFounderInvite = token.roleName === 'Founder'
    if (isFounderInvite) {
      const [{ count }] = await db.select({ count: sql<number>`count(*)::int` })
        .from(profiles).where(eq(profiles.isSuperadmin, true))
      if (count >= MAX_FOUNDERS) {
        return apiError(400, `Limite de ${MAX_FOUNDERS} founders já atingido.`)
      }
    }

    // Criar usuário
    const passwordHash = await bcrypt.hash(password, 12)
    const [user] = await db.insert(users).values({
      email: email.toLowerCase().trim(),
      passwordHash,
    }).returning()

    await db.insert(profiles).values({ id: user.id, fullName: full_name, isSuperadmin: isFounderInvite })

    // Papel do convite — token.roleName permite gerar convite pra um papel específico
    // (ex: "Founder"); sem isso, mantém o padrão histórico de sempre criar como "Admin".
    const [adminRole] = await db.select().from(organizationRoles)
      .where(and(eq(organizationRoles.organizationId, token.organizationId), eq(organizationRoles.name, token.roleName || 'Admin')))
      .limit(1)

    // Criar membro
    await db.insert(organizationMembers).values({
      organizationId: token.organizationId,
      userId: user.id,
      roleId: adminRole.id,
      status: 'active',
    })

    // Marcar token como usado
    await db.update(setupTokens).set({ usedAt: new Date() }).where(eq(setupTokens.id, token.id))

    return Response.json({ success: true, user_id: user.id })
  } catch (err: any) {
    if (err.code === '23505') return apiError(409, 'Email já cadastrado.')
    return apiError(500, err.message || 'Erro interno.')
  }
}
