/**
 * ACHAR OU CRIAR A CONVERSA DE UM NÚMERO NUMA LINHA -- o que a lupa faz
 * (/api/leads/abrir, 30/09) e o que o lembrete da visita precisa (01/10): o
 * corretor escolhido na agenda pode nunca ter falado com a gente, e o lembrete
 * é uma mensagem agendada na conversa dele.
 *
 * Um lead por pessoa em cada linha (leadDaLinha). Não envia nada.
 */
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { acharLeadDaLinha, integracaoDoTipo } from '@/lib/leadDaLinha'

/** 55 + DDD + número, com e sem o 9 (as duas formas que o banco já guarda). */
export function formasDoTelefone(digitos: string): string[] {
  const d = digitos.startsWith('55') ? digitos : '55' + digitos
  const ddd = d.slice(2, 4), resto = d.slice(4)
  const com9 = resto.length === 8 ? '9' + resto : resto
  const sem9 = resto.length === 9 && resto.startsWith('9') ? resto.slice(1) : resto
  return [...new Set([`55${ddd}${com9}`, `55${ddd}${sem9}`])]
}

export async function abrirLeadDaLinha(
  organizacao: string, telefone: string, nome: string | null, tipoDaLinha = 'whatsapp_zapi',
): Promise<{ id: string; novo: boolean } | null> {
  const digitos = String(telefone || '').replace(/\D/g, '')
  if (digitos.length < 10 || digitos.length > 13) return null
  const linha = await integracaoDoTipo(organizacao, tipoDaLinha)
  if (!linha) return null
  const formas = formasDoTelefone(digitos)
  const existente = await acharLeadDaLinha(organizacao, formas, linha)
  if (existente) return { id: existente.id, novo: false }
  const [criado] = await db.insert(leads).values({
    organizationId: organizacao,
    integrationId: linha,
    title: (nome || '').trim().slice(0, 120) || formas[0],
    phone: formas[0],
    customAttributes: { origem: 'aberta_no_crm' },
  }).returning({ id: leads.id })
  return { id: criado.id, novo: true }
}
