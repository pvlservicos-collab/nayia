/**
 * Manda um template aprovado para um número — e GRAVA A CONVERSA NO CRM.
 *
 * Tel, 26/09/2026: "e se der manda os aprovados em portugues para o tel
 * +55 92 9471-7316 para ele ver" e, depois: "não apareceu a conversa criada ao
 * enviar os templates no crm, isso tem que aparecer, mesmo que seja a gnt mesmo
 * criando pq a meta não nos avisa disso né".
 *
 * Ele está certo: a Meta só chama o nosso webhook para o que CHEGA. Quem manda
 * é o único que sabe o que foi dito, então quem manda grava -- é o que
 * `registrarEnvioNoCrm` faz aqui, com o texto do template já preenchido, o id
 * da mensagem da Meta e o lead amarrado à linha da captação.
 *
 * Só template APROVADO sai: a Meta recusa o envio de PENDING, e mandar para a
 * fila de erro sem avisar seria pior que o botão não existir.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { credencialMeta, graph, variaveisDoTemplate, corpoDoTemplate } from '@/lib/metaTemplates'
import { registrarEnvioNoCrm, textoDoTemplate } from '@/lib/registrarEnvio'

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const cred = await credencialMeta(auth.organizationId)
    if (!cred) return apiError(400, 'A API oficial ainda não está configurada aqui.')
    if (!cred.phoneNumberId) return apiError(400, 'Falta o Phone Number ID na integração da API oficial.')

    const body = await req.json().catch(() => ({}))
    const nome = String(body?.nome || '').trim()
    const idioma = String(body?.idioma || 'pt_BR')
    const para = String(body?.para || '').replace(/\D/g, '')
    if (!nome) return apiError(400, 'Diga qual template enviar.')
    if (para.length < 12) return apiError(400, 'O número parece incompleto — use 55 + DDD + número.')

    // Os valores das variáveis. Se a tela não mandar, inventa algo plausível --
    // é uma prévia, não um disparo de verdade.
    const componentes = Array.isArray(body?.componentes) ? body.componentes : []
    const variaveis = variaveisDoTemplate(componentes)
    const pedidos: string[] = Array.isArray(body?.valores) ? body.valores.map((v: any) => String(v || '')) : []
    const valores = variaveis.map((v, i) => pedidos[i] || `exemplo ${v}`)

    const parametros = variaveis.map((v, i) => (
      // variável com nome ({{nome}}) exige `parameter_name`; com número, não.
      /^\d+$/.test(v)
        ? { type: 'text', text: valores[i] }
        : { type: 'text', parameter_name: v, text: valores[i] }
    ))

    const payload: any = {
      messaging_product: 'whatsapp',
      to: para,
      type: 'template',
      template: { name: nome, language: { code: idioma } },
    }
    if (parametros.length) {
      payload.template.components = [{ type: 'body', parameters: parametros }]
    }

    const r = await graph(cred, `${cred.phoneNumberId}/messages`, { method: 'POST', body: payload })
    const idDaMeta = r?.messages?.[0]?.id || null
    const status = r?.messages?.[0]?.message_status || 'accepted'

    // A CONVERSA NO CRM. O texto vai preenchido: quem abre o chat precisa ver a
    // frase que a pessoa recebeu, não o molde com {{1}}.
    let registro: any = null
    let erroRegistro: string | null = null
    try {
      registro = await registrarEnvioNoCrm({
        organizationId: auth.organizationId,
        memberId: auth.memberId,
        telefone: para,
        texto: textoDoTemplate(corpoDoTemplate(componentes), valores),
        canal: 'whatsapp_cloud_official',
        whatsappMessageId: idDaMeta,
        origem: 'templates',
        extraMetadata: { template: nome, template_idioma: idioma, whatsapp_status: status },
      })
    } catch (err: any) {
      // A mensagem JÁ SAIU. Falhar a resposta agora faria a tela dizer "não
      // enviou" para algo que a pessoa recebeu -- pior que o registro faltando.
      // Então devolve os dois fatos e deixa a tela contar a verdade.
      erroRegistro = err?.message || 'não consegui gravar a conversa no CRM'
      console.error('[templates/enviar] template saiu mas não gravou no CRM:', err)
    }

    return Response.json({
      ok: true,
      para,
      status,
      id: idDaMeta,
      conversa: registro
        ? { leadId: registro.leadId, linha: registro.linha, criouLead: registro.criouLead }
        : null,
      erroRegistro,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'A Meta não aceitou o envio.')
  }
}
