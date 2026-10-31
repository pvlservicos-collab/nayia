import { after, NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { eq, and, isNull, sql, inArray } from 'drizzle-orm'
import { processZapiMessage, logZapiDiagnostico } from '@/lib/zapiInbound'
import { ZAPI_INTEGRATION_TYPE, TIPOS_ZAPI } from '@/lib/zapi'
import { publishEvent, channels, events } from '@/lib/realtime'
import { guardarMensagemDeGrupo } from '@/lib/gruposParceria'
import { marcarEntregaComRepeticao, situacaoDaZapi } from '@/lib/entregaDaMensagem'

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
    const instancia = body.instanceId ? String(body.instanceId) : null
    if (body.type === 'ConnectedCallback' || body.connected === true) {
      await marcarStatus(orgId, 'active', instancia)
      return NextResponse.json({ ok: true, evento: 'conectado' })
    }
    if (body.type === 'DisconnectedCallback' || body.disconnected === true) {
      await marcarStatus(orgId, 'disabled', instancia)
      await ligarAvisoDeDesconexao(orgId, instancia)
      return NextResponse.json({ ok: true, evento: 'desconectado' })
    }

    /* A SITUAÇÃO DE CADA MENSAGEM NOSSA (Pedro, 14/10/2026: "que o sistema saiba exatamente se ela foi mesmo
       entregue"). SENT = saiu do nosso aparelho, RECEIVED = chegou no celular da pessoa, READ/PLAYED = ela leu/ouviu.
       Até 14/10 este aviso era descartado aqui (e nem estava configurado na instância): o CRM só sabia que a Z-API
       tinha aceitado o pedido. Ver src/lib/entregaDaMensagem.ts. */
    if (body.type === 'MessageStatusCallback') {
      if (instancia) after(() => repassarStatus(orgId, instancia, body))
      const situacao = situacaoDaZapi(body.status)
      const ids = Array.isArray(body.ids) ? body.ids.map(String) : body.messageId ? [String(body.messageId)] : []
      if (!situacao || !ids.length || body.isGroup === true) return NextResponse.json({ ok: true, skipped: `status ${body.status}` })
      const quando = typeof body.momment === 'number' ? new Date(body.momment) : new Date()
      const n = await marcarEntregaComRepeticao(orgId, 'zapi_message_id', ids, situacao, quando, body.error ? String(body.error) : null)
      return NextResponse.json({ ok: true, status: situacao, atualizadas: n })
    }

    if (typeof body.type === 'string' && CALLBACKS_SEM_CONTEUDO.has(body.type)) {
      return NextResponse.json({ ok: true, skipped: body.type })
    }

    // Mensagem recebida (ou eco de mensagem enviada pelo celular).
    if (body.type === 'ReceivedCallback' || body.phone) {
      // MENSAGEM DE GRUPO (03/10/2026): guardada para o painel dos grupos da Parceria -- a Z-API não
      // entrega histórico, então só se lê o que for guardado aqui. Não muda nada do resto do caminho.
      if (body.isGroup === true || body.isGroup === 'true') {
        after(() => guardarMensagemDeGrupo(orgId, body)
          .catch((e) => console.error('[zapi webhook] grupo não guardado', body?.messageId, e?.message || e)))
        // SÓ GUARDA (282, 03/10): desde que a mensagem de grupo passa pelo espelho do n8n, seguir adiante faria
        // uma conversa por grupo na lista da Parceria (a da Rayssa). Grupo se lê no painel CRM › Grupos.
        return NextResponse.json({ ok: true, grupo: true }, { status: 202 })
      }
      /*
       * `?rapido=1` é só do espelho da Nay no n8n (29/09/2026): ele roda ANTES
       * do atendimento, então não pode esperar a foto baixar. Responde na hora e
       * grava logo depois. Se a gravação falhar, a conferência de cada minuto
       * (espelhoDaNay.ts) traz a mensagem -- por isso a Z-API direta, que não
       * tem essa rede, continua no caminho que espera e devolve 500.
       */
      if (req.nextUrl.searchParams.get('rapido') === '1') {
        after(() => processZapiMessage(orgId, body)
          .then(() => undefined)
          .catch((e) => console.error('[zapi webhook rápido]', body?.messageId, e?.message || e)))
        return NextResponse.json({ ok: true, fila: true }, { status: 202 })
      }
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

/**
 * O STATUS DO 8595 (Pedro, 31/10/2026: nenhuma das 1.188 mensagens enviadas pelo WhatsApp Leads tinha entregue/lida).
 * A instância da captação mandava o aviso de status só para o fluxo dela no n8n da VPS2, que grava a entrega no
 * registro da Nay (captacao_status_da_mensagem). Uma instância tem UMA URL de status: agora ela aponta para cá, e
 * o mesmo corpo segue para o n8n, sem mudar nada lá. O endereço do n8n fica em `config.status_tambem_para` da
 * integração (tem código no caminho: fora do git). Falhou o repasse: só o log; o CRM já gravou o dele.
 */
async function repassarStatus(orgId: string, instancia: string, body: unknown) {
  try {
    const r = await db.execute(sql`
      SELECT config->>'status_tambem_para' AS url FROM integrations
       WHERE organization_id = ${orgId} AND deleted_at IS NULL AND config->>'instance_id' = ${instancia}
         AND coalesce(config->>'status_tambem_para', '') <> '' LIMIT 1`)
    const url = (r.rows[0] as { url?: string } | undefined)?.url
    if (!url) return
    const resp = await fetch(url, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    })
    if (!resp.ok) console.error('[zapi webhook] repasse do status', resp.status)
  } catch (err: any) {
    console.error('[zapi webhook] repasse do status', err?.message || err)
  }
}

// 'disabled' é o valor que o enum de status da tabela usa pra "não está valendo".
/** A linha certa: a da instância que avisou; sem instância, a Parceria (28/09). */
function daInstancia(orgId: string, instancia: string | null) {
  return instancia
    ? and(eq(integrations.organizationId, orgId), inArray(integrations.type, TIPOS_ZAPI),
          isNull(integrations.deletedAt), sql`${integrations.config}->>'instance_id' = ${instancia}`)
    : and(eq(integrations.organizationId, orgId), eq(integrations.type, ZAPI_INTEGRATION_TYPE),
          isNull(integrations.deletedAt))
}

async function marcarStatus(orgId: string, status: 'active' | 'disabled', instancia: string | null = null) {
  try {
    await db
      .update(integrations)
      .set({ status, updatedAt: new Date() })
      .where(daInstancia(orgId, instancia))
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
async function ligarAvisoDeDesconexao(orgId: string, instancia: string | null = null) {
  try {
    const resultado = await db.update(integrations)
      .set({
        config: sql`COALESCE(${integrations.config}, '{}'::jsonb) || jsonb_build_object('disconnectAlertActive', true, 'disconnectedAt', ${new Date().toISOString()}::text)`,
        updatedAt: new Date(),
      })
      .where(daInstancia(orgId, instancia))
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
