/**
 * ABRIR CONVERSA COM UM NÚMERO (Pedro, 30/09/2026: "lá na aba proprietários, põe
 * uma lupinha de pesquisar por nome ou número, e se for número que não temos,
 * ele pode abrir uma conversa com esse número por lá").
 *
 * Acha o lead desse telefone na linha da Parceria (Z-API) ou cria um, pela mesma
 * regra de um lead por pessoa em cada linha (leadDaLinha). Não envia nada: a
 * conversa abre vazia e quem manda a primeira mensagem é a pessoa no CRM.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { acharLeadDaLinha, integracaoDoTipo } from '@/lib/leadDaLinha'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** 55 + DDD + número, com e sem o 9 (as duas formas que o banco já guarda). */
function formas(digitos: string): string[] {
  const d = digitos.startsWith('55') ? digitos : '55' + digitos
  const ddd = d.slice(2, 4), resto = d.slice(4)
  const com9 = resto.length === 8 ? '9' + resto : resto
  const sem9 = resto.length === 9 && resto.startsWith('9') ? resto.slice(1) : resto
  return [...new Set([`55${ddd}${com9}`, `55${ddd}${sem9}`])]
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const digitos = String(corpo?.telefone || '').replace(/\D/g, '')
    if (digitos.length < 10 || digitos.length > 13) return apiError(400, 'Número inválido: use DDD + número.')
    const nome = String(corpo?.nome || '').trim().slice(0, 120)
    // CADA LUPA ABRE NA SUA LINHA (Pedro, 30/09: "digitar um número novo lá na lupa de
    // captação para iniciar uma conversa ... cada lupa abre uma conversa com cada contato")
    const TIPO_DA_LINHA: Record<string, string> = {
      parceria: 'whatsapp_zapi', captacao: 'whatsapp_zapi_captacao', oficial: 'whatsapp_cloud_official',
    }
    const tipo = TIPO_DA_LINHA[String(corpo?.linha || 'parceria')] || 'whatsapp_zapi'
    const linha = await integracaoDoTipo(auth.organizationId, tipo)
    if (!linha) return apiError(400, 'Essa linha de WhatsApp não está configurada.')

    const [principal] = formas(digitos)
    const existente = await acharLeadDaLinha(auth.organizationId, formas(digitos), linha)
    if (existente) return Response.json({ id: existente.id, novo: false })

    const [criado] = await db.insert(leads).values({
      organizationId: auth.organizationId,
      integrationId: linha,
      title: nome || principal,
      phone: principal,
      customAttributes: { origem: 'aberta_no_crm' },
    }).returning({ id: leads.id })
    return Response.json({ id: criado.id, novo: true })
  } catch (err: any) {
    console.error('[abrir conversa]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui abrir a conversa.')
  }
}
