/**
 * O CHECKLIST PREENCHIDO NO CRM VAI AO TEL (Pedro, 30/09/2026: "ao preencher o
 * checklist é enviado ao Tel no número pessoal dele, por enquanto").
 *
 * O texto é montado em lib/checklistFechamento (montarTexto) e sai pela caixa
 * da Nay para o número do Tel (nai_config.tel_telefone), pela função
 * crm_checklist_preenchido do banco da Nay (Arquivos/nai/198).
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { montarTexto, type TipoChecklist } from '@/lib/checklistFechamento'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const tipo: TipoChecklist | null = corpo?.tipo === 'venda' ? 'venda' : corpo?.tipo === 'locacao' ? 'locacao' : null
    if (!tipo) return apiError(400, 'Escolha: aluguel ou venda.')
    const valores = corpo?.valores && typeof corpo.valores === 'object' ? corpo.valores : {}

    let quem = 'CRM'
    if (auth.memberId) {
      const [m] = await db.select({ nome: profiles.fullName }).from(organizationMembers)
        .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
        .where(eq(organizationMembers.id, auth.memberId)).limit(1)
      quem = m?.nome || 'equipe'
    }
    const texto = montarTexto(tipo, valores, quem)
    const r = await naydb().query('SELECT * FROM crm_checklist_preenchido($1, $2, $3)', [tipo, texto, quem])
    const l = r.rows[0]
    return l?.ok ? Response.json({ ok: true, mensagem: l.mensagem }) : apiError(400, l?.mensagem || 'A Nay não mandou.')
  } catch (err: any) {
    console.error('[checklist preenchido]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar o checklist ao Tel.')
  }
}
