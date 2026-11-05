/**
 * GET /api/v3/sucesso-das-conversas -> { notas: { "<linha>:<8 últimos dígitos>": { nota, resumo, erros, dia } } }
 *
 * A TAXA DE SUCESSO DAS CONVERSAS (Pedro, 05/11/2026: "revisa as conversas do atendimento hoje, vê se as Nays estão
 * respondendo certinho, coloca uma taxa de sucesso em cada conversa que só aparece para o meu login e o do Tel, nas que
 * tu revisar"). A nota (0 a 100) de cada conversa revisada vem do banco da Nay (crm_sucesso_das_conversas, migração
 * 610): a mais recente dos últimos 3 dias. SÓ responde para os logins Pedro e Tel (administradores); para os outros, 403
 * e nenhuma nota sai do servidor.
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationRoles, profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const QUEM_VE = ['pedro', 'tel']

async function podeVer(userId: string | null, roleId: string | null): Promise<boolean> {
  if (!userId) return false
  const [p] = await db.select({ nome: profiles.fullName, superadmin: profiles.isSuperadmin }).from(profiles).where(eq(profiles.id, userId)).limit(1)
  const primeiro = String(p?.nome || '').trim().split(/\s+/)[0].toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  if (!QUEM_VE.includes(primeiro)) return false
  if (p?.superadmin) return true
  if (!roleId) return false
  const [r] = await db.select({ nome: organizationRoles.name, permissoes: organizationRoles.permissions }).from(organizationRoles)
    .where(eq(organizationRoles.id, roleId)).limit(1)
  return ['admin', 'administrador', 'owner'].includes(String(r?.nome || '').toLowerCase()) || !!(r?.permissoes as any)?.['*']
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!(await podeVer(auth.userId, (auth as any).roleId ?? null))) return apiError(403, 'Só os logins Pedro e Tel veem a taxa de sucesso.')
    const r = await naydb().query('SELECT fone8, linha, dia, nota, resumo, erros FROM crm_sucesso_das_conversas(3)')
    const notas: Record<string, { nota: number; resumo: string | null; erros: string[]; dia: string }> = {}
    for (const l of r.rows as Array<{ fone8: string; linha: string; dia: string | Date; nota: number; resumo: string | null; erros: unknown }>) {
      notas[`${l.linha}:${l.fone8}`] = {
        nota: Number(l.nota), resumo: l.resumo, erros: Array.isArray(l.erros) ? (l.erros as string[]) : [],
        dia: (l.dia instanceof Date ? l.dia.toISOString() : String(l.dia)).slice(0, 10),
      }
    }
    return Response.json({ notas })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a taxa de sucesso.')
  }
}
