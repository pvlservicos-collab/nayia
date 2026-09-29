/**
 * GET  -> todos os templates da conta, com o status que a Meta está dando agora.
 * POST -> cria um template novo e manda para a fila de aprovação da Meta.
 *
 * Tel, 26/09/2026: "para eu acompanhar status se ja aprovou e cadastrar novos
 * por la".
 *
 * Criar template NÃO manda mensagem para ninguém: entra na fila da Meta (sai em
 * minutos, às vezes horas). Enquanto está PENDING não dá para usar.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { credencialMeta, graph, corpoDoTemplate, variaveisDoTemplate } from '@/lib/metaTemplates'

const CAMPOS = 'id,name,status,category,language,components,quality_score,rejected_reason'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const cred = await credencialMeta(auth.organizationId)
    if (!cred) {
      return Response.json({
        templates: [],
        aviso: 'A API oficial ainda não está configurada aqui. Cadastre em Integrações → WhatsApp Cloud API '
             + '(WABA ID, Phone Number ID e o token do usuário de sistema).',
      })
    }

    const r = await graph(cred, `${cred.wabaId}/message_templates?limit=100&fields=${CAMPOS}`)
    const templates = (r?.data || []).map((t: any) => ({
      id: t.id,
      nome: t.name,
      status: t.status,
      categoria: t.category,
      idioma: t.language,
      corpo: corpoDoTemplate(t.components),
      variaveis: variaveisDoTemplate(t.components),
      componentes: t.components,
      qualidade: t.quality_score?.score || null,
      motivoRecusa: t.rejected_reason && t.rejected_reason !== 'NONE' ? t.rejected_reason : null,
    }))

    // aprovados primeiro? não: PENDING primeiro, que é o que ele quer olhar.
    const ordem: Record<string, number> = { PENDING: 0, IN_APPEAL: 1, REJECTED: 2, PAUSED: 3, APPROVED: 4 }
    templates.sort((a: any, b: any) =>
      (ordem[a.status] ?? 9) - (ordem[b.status] ?? 9) || a.nome.localeCompare(b.nome))

    return Response.json({
      templates,
      fonte: cred.fonte,
      waba: cred.wabaId,
      numeroConfigurado: !!cred.phoneNumberId,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui ler os templates da Meta.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const cred = await credencialMeta(auth.organizationId)
    if (!cred) return apiError(400, 'A API oficial ainda não está configurada aqui.')

    const body = await req.json().catch(() => ({}))
    const nome = String(body?.nome || '').trim().toLowerCase().replace(/[^a-z0-9_]/g, '_')
    const corpo = String(body?.corpo || '').trim()
    if (!nome) return apiError(400, 'Dê um nome ao template (só letras minúsculas, números e _).')
    if (!corpo) return apiError(400, 'Escreva o texto do template.')

    const categoria = ['MARKETING', 'UTILITY', 'AUTHENTICATION'].includes(body?.categoria)
      ? body.categoria : 'UTILITY'
    const idioma = String(body?.idioma || 'pt_BR')

    const componentes: any[] = []
    const cabecalho = String(body?.cabecalho || '').trim()
    if (cabecalho) componentes.push({ type: 'HEADER', format: 'TEXT', text: cabecalho })
    componentes.push({ type: 'BODY', text: corpo })
    const rodape = String(body?.rodape || '').trim()
    if (rodape) componentes.push({ type: 'FOOTER', text: rodape })

    // Botões de resposta rápida, um por linha no campo da tela. A Meta aceita
    // até 3 -- mandar 4 faz ela recusar o template inteiro, então cortamos aqui.
    const botoes = String(body?.botoes || '').split('\n')
      .map((b) => b.trim()).filter(Boolean).slice(0, 3)
    if (botoes.length) {
      componentes.push({ type: 'BUTTONS', buttons: botoes.map((text) => ({ type: 'QUICK_REPLY', text })) })
    }

    // O exemplo é OBRIGATÓRIO quando o texto tem {{1}}: sem ele a Meta recusa
    // dizendo "missing example". A tela pede um valor por variável.
    const variaveis = variaveisDoTemplate(componentes)
    const exemplos: string[] = Array.isArray(body?.exemplos) ? body.exemplos.map((x: any) => String(x || '')) : []
    if (variaveis.length) {
      const corpoComp = componentes.find((c) => c.type === 'BODY')
      corpoComp.example = {
        body_text: [variaveis.map((v, i) => exemplos[i] || `exemplo ${v}`)],
      }
    }

    const criado = await graph(cred, `${cred.wabaId}/message_templates`, {
      method: 'POST',
      body: { name: nome, language: idioma, category: categoria, components: componentes },
    })
    return Response.json({ ok: true, id: criado?.id, status: criado?.status || 'PENDING', nome })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'A Meta não aceitou o template.')
  }
}
