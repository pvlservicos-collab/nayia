/**
 * POST /api/webhooks/captacao-oficial
 * A Nay de captação responde pelo NÚMERO OFICIAL (8456-0874).
 *
 * Pedro, 28/09/2026: "a nay de captação vai agora conversar pelo número
 * oficial". O fluxo da captação (n8n, na srv1877774) sempre respondeu pela
 * Z-API. Para o número oficial, quem manda é o CRM, por dois motivos:
 *
 *   1. o token da Meta mora aqui (META_TOKEN no .env) e não sai daqui;
 *   2. a Meta não devolve em webhook o que a gente manda -- quem manda grava
 *      (`registrarEnvioNoCrm`), e é isso que põe a resposta da Nay na conversa
 *      da aba WhatsApp Oficial.
 *
 * O caminho de ida é o webhook da Meta (`/api/webhooks/facebook`), que repassa
 * para a captação o que chega no número oficial.
 *
 * Protegido por `x-captacao-segredo` = CAPTACAO_OFICIAL_SEGREDO (.env): o
 * /api/webhooks é público, e sem isso qualquer um mandaria mensagem pelo
 * número oficial. Sempre responde 200 com { ok, messageId, erro } -- o n8n
 * grava a falha ('Falhou') em vez de derrubar o laço de balões.
 *
 * O MODELO QUE ABRE A CONVERSA (Pedro, 08/10/2026: "prepara a nay captação para
 * rodar no número de api oficial ... mandando o modelo"). Fora da janela de 24h
 * a Meta só aceita modelo (template) aprovado, e é com ele que a captação
 * começa. O mesmo endereço aceita, no lugar de `texto`:
 *
 *   { telefone, template: { nome, idioma, valores: ["Sr. Pedro"] } }
 *
 * O modelo é lido da Meta na hora (só sai se estiver APROVADO e se vierem todos
 * os valores das variáveis), e a resposta traz o `texto` que a pessoa recebeu,
 * já preenchido: é o que quem chama grava como a primeira mensagem da conversa.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { getChannelAdapter } from '@/lib/channels/registry'
import { registrarEnvioNoCrm, textoDoTemplate } from '@/lib/registrarEnvio'
import { corpoDoTemplate, credencialMeta, graph, variaveisDoTemplate } from '@/lib/metaTemplates'

/** Manda um modelo aprovado e grava a conversa. Nunca lança: devolve { ok, messageId, texto, erro }. */
async function mandarModelo(organizationId: string, telefone: string, pedido: any): Promise<Response> {
  const nome = String(pedido?.nome || '').trim()
  const idioma = String(pedido?.idioma || 'pt_BR').trim()
  const valores: string[] = Array.isArray(pedido?.valores) ? pedido.valores.map((v: any) => String(v ?? '').trim()) : []
  const nao = (erro: string) => Response.json({ ok: false, erro, messageId: null, texto: null })
  try {
    const cred = await credencialMeta(organizationId)
    if (!cred || !cred.phoneNumberId) return nao('a API oficial não está configurada no CRM')
    const lista = await graph(cred, `${cred.wabaId}/message_templates?name=${encodeURIComponent(nome)}&fields=name,language,status,components&limit=50`)
    const modelo = (lista?.data || []).find((x: any) => x?.name === nome && x?.language === idioma)
    if (!modelo) return nao(`não achei o modelo ${nome} (${idioma}) na Meta`)
    if (modelo.status !== 'APPROVED') return nao(`o modelo ${nome} está ${modelo.status} na Meta: só o aprovado sai`)
    const variaveis = variaveisDoTemplate(modelo.components || [])
    if (variaveis.some((_, i) => !valores[i])) return nao(`o modelo ${nome} pede ${variaveis.length} valor(es) e veio a menos`)

    const payload: any = { messaging_product: 'whatsapp', to: telefone, type: 'template', template: { name: nome, language: { code: idioma } } }
    if (variaveis.length) {
      payload.template.components = [{
        type: 'body',
        // variável com nome ({{nome}}) exige `parameter_name`; com número, não
        parameters: variaveis.map((v, i) => (/^\d+$/.test(v) ? { type: 'text', text: valores[i] } : { type: 'text', parameter_name: v, text: valores[i] })),
      }]
    }
    const r = await graph(cred, `${cred.phoneNumberId}/messages`, { method: 'POST', body: payload })
    const messageId: string | null = r?.messages?.[0]?.id || null
    const texto = textoDoTemplate(corpoDoTemplate(modelo.components || []), valores)
    if (!messageId) return Response.json({ ok: false, erro: 'a Meta aceitou o pedido mas não devolveu o id da mensagem', messageId: null, texto })
    try {
      await registrarEnvioNoCrm({
        organizationId, telefone, texto, canal: 'whatsapp_cloud_official', whatsappMessageId: messageId, origem: 'ai_agent',
        extraMetadata: { automated: true, agente: 'nay_captacao', template: nome, template_idioma: idioma },
      })
    } catch (err) {
      // O modelo JÁ SAIU: falhar agora faria quem chamou achar que não saiu.
      console.error('[captacao-oficial] o modelo saiu, mas não gravou no CRM:', err)
    }
    return Response.json({ ok: true, messageId, texto })
  } catch (err: any) {
    console.error('[captacao-oficial] o modelo não saiu:', err?.message || err)
    return nao(err?.message || 'erro ao enviar o modelo')
  }
}

export async function POST(req: NextRequest) {
  const segredo = process.env.CAPTACAO_OFICIAL_SEGREDO
  if (!segredo || req.headers.get('x-captacao-segredo') !== segredo) {
    return Response.json({ ok: false, erro: 'não autorizado', messageId: null }, { status: 401 })
  }

  const body = await req.json().catch(() => ({} as any))
  const telefone = String(body?.telefone ?? '').replace(/\D/g, '')
  const texto = String(body?.texto ?? '').trim()
  const pedeModelo = !!String(body?.template?.nome ?? '').trim()
  if (telefone.length < 12 || (!texto && !pedeModelo)) {
    return Response.json({ ok: false, erro: 'telefone ou texto faltando', messageId: null })
  }

  const [linha] = await db
    .select({ id: integrations.id, organizationId: integrations.organizationId })
    .from(integrations)
    .where(and(eq(integrations.type, 'whatsapp_cloud_official'), isNull(integrations.deletedAt)))
    .limit(1)
  if (!linha) return Response.json({ ok: false, erro: 'a linha oficial não existe', messageId: null })
  if (pedeModelo) return mandarModelo(linha.organizationId, telefone, body.template)

  let messageId: string | null = null
  try {
    const r = await getChannelAdapter('whatsapp_cloud_official')
      .sendText(linha.organizationId, linha.id, telefone, texto, false)
    messageId = r.externalId || null
  } catch (err: any) {
    // Fora da janela de 24h a Meta recusa texto livre (só template). O erro
    // dela volta para o n8n, que grava a mensagem como 'Falhou'.
    console.error('[captacao-oficial] a resposta não saiu:', err?.message || err)
    return Response.json({ ok: false, erro: err?.message || 'erro ao enviar', messageId: null })
  }

  try {
    await registrarEnvioNoCrm({
      organizationId: linha.organizationId,
      telefone,
      texto,
      canal: 'whatsapp_cloud_official',
      whatsappMessageId: messageId,
      // 'ai_agent' e `automated`: resposta de robô não conta como atendimento
      // de gente na lista do chat (ver `manual` em /api/leads)
      origem: 'ai_agent',
      extraMetadata: { automated: true, agente: 'nay_captacao' },
    })
  } catch (err) {
    // A mensagem JÁ SAIU: falhar agora faria o n8n achar que não saiu.
    console.error('[captacao-oficial] saiu, mas não gravou no CRM:', err)
  }

  return Response.json({ ok: true, messageId })
}
