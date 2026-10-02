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
import { abrirLeadDaLinha } from '@/lib/abrirLead'
import { integracaoDoTipo } from '@/lib/leadDaLinha'
import { recusaAbrirNaCaptacao } from '@/lib/captacaoSoRespondeServidor'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

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
    // quem só responde na captação não abre conversa por lá (Pedro, 02/10)
    const recusa = await recusaAbrirNaCaptacao(auth.memberId, tipo)
    if (recusa) return apiError(403, recusa)

    // achar ou criar: a mesma regra do lembrete da visita (src/lib/abrirLead.ts)
    const aberto = await abrirLeadDaLinha(auth.organizationId, digitos, nome, tipo)
    if (!aberto) return apiError(400, 'Não consegui abrir a conversa com esse número.')
    return Response.json(aberto)
  } catch (err: any) {
    console.error('[abrir conversa]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui abrir a conversa.')
  }
}
