import { db } from '@/lib/db'
import { integrations, integrationSecrets } from '@/lib/schema'
import { eq, isNull, and } from 'drizzle-orm'
import { processEvolutionMessage } from '@/lib/evolutionInbound'

/**
 * GET/POST /api/cron/evolution-reconcile
 * Rede de segurança pro webhook em tempo real da Evolution (src/app/api/webhooks/
 * evolution/route.ts): busca as mensagens mais recentes direto na própria Evolution
 * API (/chat/findMessages, que guarda o histórico real da instância) e reprocessa
 * cada uma pela mesma lógica do webhook (processEvolutionMessage) — que já é
 * idempotente (dedup por evolution_message_id), então reprocessar mensagem que já
 * está no CRM só cai no skip 'duplicate', sem custo além da consulta.
 *
 * Existe porque confirmamos em produção (2026-07-13) que o webhook pode perder uma
 * mensagem real sem deixar rastro nenhum (uma foto+legenda chegou como
 * "messages.update" em vez de "messages.upsert" — já corrigido — mas webhook é
 * best-effort por natureza: uma falha de rede, um restart da Evolution, etc. podem
 * fazer o mesmo independente de bug no nosso código).
 *
 * Roda a cada 1 min (o mínimo que a Vercel permite — ver vercel.json). Intervalo
 * curto de propósito: confirmamos em 2026-07-15 que áudio enviado direto do WhatsApp
 * Nº2 nunca chega pelo webhook em tempo real (causa exata não identificada — só a
 * reconciliação recupera), então o intervalo do cron é literalmente o atraso que o
 * usuário sente pra ver um áudio enviado direto do celular aparecer no CRM.
 *
 * Também: até 2026-07-15 esse cron nunca rodou de verdade (rota faltava em
 * `publicPaths` do middleware — ver memória do projeto) — se voltar a "não recuperar
 * nada", checar isso antes de suspeitar de outra causa.
 */
const PAGE_SIZE = 300

async function reconcileIntegration(orgId: string, integrationId: string) {
  const [row] = await db
    .select({ config: integrations.config, secret: integrationSecrets.secret })
    .from(integrations)
    .leftJoin(integrationSecrets, eq(integrationSecrets.integrationId, integrations.id))
    .where(eq(integrations.id, integrationId))
    .limit(1)

  const instanceName = (row?.config as any)?.instanceName
  const apiKey = (row?.secret as any)?.api_key || process.env.EVOLUTION_API_KEY
  const server = (row?.config as any)?.apiUrl || process.env.EVOLUTION_API_URL
  if (!instanceName || !server) return { orgId, integrationId, error: 'config incompleta', checked: 0, created: 0 }

  const res = await fetch(`${server}/chat/findMessages/${instanceName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: apiKey },
    body: JSON.stringify({ page: 1, offset: PAGE_SIZE }),
  })
  if (!res.ok) return { orgId, integrationId, error: `findMessages HTTP ${res.status}`, checked: 0, created: 0 }

  const data = await res.json().catch(() => null)
  const records: any[] = data?.messages?.records || []

  let created = 0
  let errors = 0
  for (const record of records) {
    try {
      const result = await processEvolutionMessage(orgId, record, { instance: instanceName })
      if (result.status === 'created') created++
    } catch (err) {
      errors++
      console.error('[evolution-reconcile] falha processando mensagem', record?.key?.id, err)
    }
  }

  return { orgId, integrationId, checked: records.length, created, errors }
}

async function reconcile() {
  try {
    const rows = await db
      .select({ id: integrations.id, organizationId: integrations.organizationId })
      .from(integrations)
      .where(and(eq(integrations.type, 'whatsapp_evolution'), isNull(integrations.deletedAt)))

    const results = []
    for (const row of rows) {
      results.push(await reconcileIntegration(row.organizationId, row.id))
    }

    return Response.json({ status: 'ok', results })
  } catch (err: any) {
    return Response.json({ status: 'error', message: err.message || 'Erro interno.' }, { status: 500 })
  }
}

export const GET = reconcile
export const POST = reconcile
