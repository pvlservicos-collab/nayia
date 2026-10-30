/**
 * AS CONVERSAS QUE JÁ EXISTEM COM UM NÚMERO, em cada linha de WhatsApp (Pedro, 30/10/2026: "Contactar dono: primeiro
 * checa automático se já tem conversa; se não, abre o menu criar contato para selecionar o número"). Só procura:
 * não cria nada (quem cria é /api/leads/abrir).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { acharLeadDaLinha, integracaoDoTipo } from '@/lib/leadDaLinha'
import { formasDoTelefone } from '@/lib/abrirLead'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const LINHAS: Array<{ linha: 'parceria' | 'captacao'; tipo: string }> = [
  { linha: 'parceria', tipo: 'whatsapp_zapi' },
  { linha: 'captacao', tipo: 'whatsapp_zapi_captacao' },
]

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const digitos = String(corpo?.telefone || '').replace(/\D/g, '')
    if (digitos.length < 10 || digitos.length > 13) return apiError(400, 'Número inválido: use DDD + número.')
    const formas = formasDoTelefone(digitos)
    const linhas = await Promise.all(LINHAS.map(async ({ linha, tipo }) => {
      const integracao = await integracaoDoTipo(auth.organizationId, tipo)
      if (!integracao) return { linha, configurada: false, leadId: null as string | null }
      const lead = await acharLeadDaLinha(auth.organizationId, formas, integracao)
      return { linha, configurada: true, leadId: lead?.id ?? null }
    }))
    return Response.json({ linhas })
  } catch (err: any) {
    console.error('[conversas do número]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui conferir as conversas.')
  }
}
