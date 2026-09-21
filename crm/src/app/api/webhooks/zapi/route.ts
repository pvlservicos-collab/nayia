import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { eq, and, isNull, sql } from 'drizzle-orm'
import { processZapiMessage, logZapiDiagnostico } from '@/lib/zapiInbound'
import { ZAPI_INTEGRATION_TYPE } from '@/lib/zapi'
import { publishEvent, channels, events } from '@/lib/realtime'

/**
 * Webhook único da Z-API.
 *
 * A Z-API tem um webhook por evento (mensagem recebida, status da mensagem,
 * conectado, desconectado), mas todos podem apontar pro mesmo endereço — é o que
 * `update-every-webhooks` faz. Ter uma URL só evita o erro clássico de configurar
 * três e esquecer justamente o de mensagem recebida; a separação acontece aqui,
 * pelo campo `type` do corpo.
 *
 * A organização vai na query (`?org_id=`), igual ao webhook da Evolution: a Z-API
 * não tem como carregar isso no payload, e o CRM é multiorganização.
 */

/** Callbacks que existem e não são conteúdo — reconhecidos pra não virar diagnóstico. */
const CALLBACKS_SEM_CONTEUDO = new Set([
  'MessageStatusCallback',
  'DeliveryCallback',
  'ReadCallback',
  'PresenceChatCallback',
])

export async function POST(req: NextRequest) {
  try {
    const orgId = req.nextUrl.searchParams.get('org_id')
    if (!orgId) return NextResponse.json({ ok: false, error: 'org_id ausente' }, { status: 400 })

    const body = await req.json().catch(() => null)
    if (!body || typeof body !== 'object') {
      return NextResponse.json({ ok: false, error: 'corpo inválido' }, { status: 400 })
    }

    // Conectou / desconectou: reflete no status da integração, que é o que a tela
    // de configuração mostra. Sem isto, uma instância caída só apareceria como
    // "mensagens pararam de chegar", sem ninguém saber por quê.
    if (body.type === 'ConnectedCallback' || body.connected === true) {
      await marcarStatus(orgId, 'active')
      return NextResponse.json({ ok: true, evento: 'conectado' })
    }
    if (body.type === 'DisconnectedCallback' || body.disconnected === true) {
      await marcarStatus(orgId, 'disabled')
      await ligarAvisoDeDesconexao(orgId)
      return NextResponse.json({ ok: true, evento: 'desconectado' })
    }

    if (typeof body.type === 'string' && CALLBACKS_SEM_CONTEUDO.has(body.type)) {
      return NextResponse.json({ ok: true, skipped: body.type })
    }

    // Mensagem recebida (ou eco de mensagem enviada pelo celular).
    if (body.type === 'ReceivedCallback' || body.phone) {
      const resultado = await processZapiMessage(orgId, body)
      if (resultado.status === 'created') {
        return NextResponse.json({ ok: true, activityId: resultado.activityId })
      }
      return NextResponse.json({ ok: true, skipped: resultado.reason })
    }

    // Chegou algo que não sabemos ler: registra o payload em vez de descartar em
    // silêncio. Foi assim que os formatos desconhecidos da Evolution apareceram.
    await logZapiDiagnostico('evento_desconhecido', orgId, body)
    return NextResponse.json({ ok: true, skipped: 'evento desconhecido' })
  } catch (err: any) {
    console.error('[zapi webhook]', err)
    // 500 faz a Z-API reenviar, e o processamento é idempotente (dedupe por
    // messageId), então repetir é seguro e melhor que perder a mensagem.
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 })
  }
}

// 'disabled' é o valor que o enum de status da tabela usa pra "não está valendo".
async function marcarStatus(orgId: string, status: 'active' | 'disabled') {
  try {
    await db
      .update(integrations)
      .set({ status, updatedAt: new Date() })
      .where(and(
        eq(integrations.organizationId, orgId),
        eq(integrations.type, ZAPI_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      ))
  } catch (err) {
    console.error('[zapi webhook] falha ao atualizar status da integração', err)
  }
}

/**
 * Liga o aviso fixo "INSTÂNCIA DESCONECTADA!" em cima do chat. Fica em
 * `integrations.config` (não em `status`, que já reflete conectado/desconectado
 * sozinho) porque precisa sobreviver a uma reconexão automática — só um humano
 * fechando o aviso (PUT .../zapi ação "fechar_aviso") desliga.
 *
 * UPDATE só, com merge de jsonb direto no Postgres (`config || '{...}'`) — não
 * faz o SELECT-então-UPDATE que tinha antes. Foram dois round-trips separados
 * pro banco pra uma única gravação; a primeira vez que isso rodou em produção,
 * o status desconectado gravou (marcarStatus, uma query só) mas o aviso não
 * (essa função, que dependia de duas em sequência) — sem log de erro nenhum,
 * o que só reforça o problema: alguma das duas falhou ali no meio e o catch
 * escondeu qual. Uma query atômica fecha essa lacuna específica; o log virou
 * console.error(err.message) pra próxima vez não ficar sem pista nenhuma.
 */
async function ligarAvisoDeDesconexao(orgId: string) {
  try {
    const resultado = await db.update(integrations)
      .set({
        config: sql`COALESCE(${integrations.config}, '{}'::jsonb) || jsonb_build_object('disconnectAlertActive', true, 'disconnectedAt', ${new Date().toISOString()}::text)`,
        updatedAt: new Date(),
      })
      .where(and(
        eq(integrations.organizationId, orgId),
        eq(integrations.type, ZAPI_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      ))
      .returning({ id: integrations.id })

    if (resultado.length === 0) {
      console.error(`[zapi webhook] aviso de desconexão: nenhuma integração Z-API encontrada pra org ${orgId}`)
      return
    }

    await publishEvent(channels.orgLeads(orgId), events.INTEGRATION_DISCONNECT_ALERT, { active: true })
  } catch (err: any) {
    console.error('[zapi webhook] falha ao ligar aviso de desconexão:', err?.message || err)
  }
}

/** A Z-API valida a URL com um GET antes de salvar o webhook. */
export async function GET() {
  return NextResponse.json({ ok: true, message: 'Webhook Z-API ativo' })
}
