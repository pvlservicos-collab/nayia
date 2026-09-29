/**
 * O relatório da captação, pelo botão "Enviar relatório ao Tel" da barra
 * (Pedro, 29/09/2026).
 *
 * GET  -- o texto, para a tela mostrar antes de mandar.
 * POST -- manda. O texto é o do relatório das 18h (migração 178), para o
 *         mesmo número (captacao_config.telefone_relatorio), pela linha da
 *         captação -- o mesmo caminho do das 18h. O eco da Z-API grava a
 *         mensagem na conversa, como qualquer envio da linha.
 *
 * Um envio por minuto: dois cliques (ou duas telas) não mandam duas vezes.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { relatorioDaCaptacao } from '@/lib/nayLeitura'
import { sendZapiMessage } from '@/lib/zapi'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

let ultimoEnvio = 0

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const { telefone, mensagem } = await relatorioDaCaptacao()
    return Response.json({ mensagem, temDestino: !!telefone })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui montar o relatório.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const { organizationId } = await authenticateRequest(req)
    if (Date.now() - ultimoEnvio < 60_000) {
      return apiError(429, 'O relatório acabou de ser enviado. Espere um minuto para mandar de novo.')
    }
    const { telefone, mensagem } = await relatorioDaCaptacao()
    if (!telefone) return apiError(400, 'A captação não tem o número do relatório configurado (telefone_relatorio).')
    if (!mensagem) return apiError(500, 'O relatório veio vazio.')

    const [linha] = await db
      .select({ id: integrations.id })
      .from(integrations)
      .where(and(
        eq(integrations.organizationId, organizationId),
        eq(integrations.type, 'whatsapp_zapi_captacao'),
        isNull(integrations.deletedAt),
      ))
      .limit(1)
    if (!linha) return apiError(400, 'A linha da captação não está configurada no CRM.')

    ultimoEnvio = Date.now()
    try {
      await sendZapiMessage(organizationId, telefone, mensagem, linha.id)
    } catch (err) {
      ultimoEnvio = 0
      throw err
    }
    return Response.json({ enviado: true, mensagem })
  } catch (err: any) {
    console.error('[relatório da captação]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar o relatório.')
  }
}
