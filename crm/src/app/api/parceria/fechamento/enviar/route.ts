/**
 * POST /api/parceria/fechamento/enviar
 * { lead, tipo, valores, documentos: [activityId] } -> { ok, mensagem, enviados, semLink }
 * "No fim, enviar ao Tel tudo organizado" (Pedro, 30/09/2026): o checklist
 * (montarTexto, como o POST /checklist) e, em seguida, os documentos separados em
 * CORRETOR e CLIENTE, cada um com o rótulo e um link assinado de 7 dias. Sai pela
 * caixa da Nay para o número do Tel (crm_checklist_preenchido, até 3800 caracteres
 * por mensagem: a lista de documentos se divide se precisar).
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { enderecoParaFora, relativoDoArmazem } from '@/lib/armazem'
import { montarTexto, type TipoChecklist } from '@/lib/checklistFechamento'
import { atividadesDoLead, itensDoFechamento, leadDoFechamento, type ItemDoFechamento } from '@/lib/fechamentoServidor'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PAPEL_ROTULO: Record<string, string> = { inquilino: 'inquilino', comprador: 'comprador', vendedor: 'vendedor', corretor: 'corretor' }

async function mandarAoTel(tipo: TipoChecklist, texto: string, quem: string): Promise<{ ok: boolean; mensagem: string }> {
  const r = await naydb().query('SELECT * FROM crm_checklist_preenchido($1, $2, $3)', [tipo, texto, quem])
  const l = r.rows[0]
  return { ok: !!l?.ok, mensagem: l?.mensagem || 'A Nay não mandou.' }
}

/** Divide as linhas em mensagens de até ~3700 caracteres, com o título repetido. */
function emMensagens(titulo: string, linhas: string[]): string[] {
  const saida: string[] = []
  let atual = titulo
  for (const l of linhas) {
    if ((atual + '\n' + l).length > 3700) { saida.push(atual); atual = titulo + ' (continuação)' }
    atual += '\n' + l
  }
  if (atual !== titulo) saida.push(atual)
  return saida
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const tipo: TipoChecklist | null = corpo?.tipo === 'venda' ? 'venda' : corpo?.tipo === 'locacao' ? 'locacao' : null
    if (!tipo) return apiError(400, 'Escolha: aluguel ou venda.')
    const lead = await leadDoFechamento(auth.organizationId, String(corpo?.lead || ''))
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    const valores = corpo?.valores && typeof corpo.valores === 'object' ? corpo.valores : {}
    const pedidos = new Set<string>((Array.isArray(corpo?.documentos) ? corpo.documentos : []).map(String))

    let quem = 'CRM'
    if (auth.memberId) {
      const [m] = await db.select({ nome: profiles.fullName }).from(organizationMembers)
        .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
        .where(eq(organizationMembers.id, auth.memberId)).limit(1)
      quem = m?.nome || 'equipe'
    }

    // 1. o checklist
    const primeira = await mandarAoTel(tipo, montarTexto(tipo, valores, quem), quem)
    if (!primeira.ok) return apiError(400, primeira.mensagem)

    // 2. os documentos, só os pedidos e só os desta conversa
    const itens = (await itensDoFechamento(await atividadesDoLead(auth.organizationId, lead.id), lead.id, tipo))
      .filter((i) => pedidos.has(i.activityId))
    const semLink: string[] = []
    const linha = (i: ItemDoFechamento): string | null => {
      if (!relativoDoArmazem(i.url)) { semLink.push(i.activityId); return null }
      try {
        const rotulo = i.documento?.rotulo || 'Documento sem nome'
        const papel = i.papel && i.papel !== 'corretor' ? ` (${PAPEL_ROTULO[i.papel]})` : ''
        return `• ${rotulo}${papel}: ${enderecoParaFora(i.url)}`
      } catch { semLink.push(i.activityId); return null }
    }
    const doCorretor = itens.filter((i) => i.dono === 'corretor').map(linha).filter(Boolean) as string[]
    const doCliente = itens.filter((i) => i.dono !== 'corretor').map(linha).filter(Boolean) as string[]
    const titulo = `📎 *DOCUMENTOS DO FECHAMENTO* — ${lead.nome}${lead.telefone ? ' (' + lead.telefone + ')' : ''}`
    const linhas = [
      ...(doCorretor.length ? ['', '*Documentos do corretor*', ...doCorretor] : []),
      ...(doCliente.length ? ['', '*Documentos do cliente*', ...doCliente] : []),
      ...(doCorretor.length || doCliente.length ? ['', '_Os links valem 7 dias._'] : []),
    ]
    for (const texto of emMensagens(titulo, linhas)) {
      const r = await mandarAoTel(tipo, texto, quem)
      if (!r.ok) return apiError(400, 'O checklist foi, mas os documentos não: ' + r.mensagem)
    }
    return Response.json({
      ok: true,
      mensagem: 'Enviado ao Tel.',
      enviados: { corretor: doCorretor.length, cliente: doCliente.length },
      semLink,
    })
  } catch (err: any) {
    console.error('[fechamento enviar]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar ao Tel.')
  }
}
