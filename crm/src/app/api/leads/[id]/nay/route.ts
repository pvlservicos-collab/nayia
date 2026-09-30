/**
 * GET /api/leads/{id}/nay -- o que a Nay sabe desta pessoa, para o card do
 * lado da conversa da Parceria (29/09/2026): as marcas (proprietário de
 * quais imóveis, corretor, visita aberta, o Tel com a conversa) e o histórico
 * do que ela pediu, recebeu e visitou. Pedro: "faz informações que fazem
 * sentido para a gente, e o histórico do que aquele contato já pediu".
 *
 * POST { acao: 'parar' | 'voltar' } -- os botões "Parar Nay" e "Nay voltar a
 * atender" (Pedro, 29/09: "o sistema vai pegar o contexto e a última mensagem
 * e mandar para a Nay caso a Nay tenha esquecido"). Voltar solta a conversa
 * (migração 176) e, se a última palavra é da pessoa, reentrega à NAI o que ela
 * escreveu desde a nossa última mensagem -- pelo mesmo webhook do fluxo
 * antigo, com um id próprio (CRMNAY...), que a trava de repetição da Nay deixa
 * passar e que a entrada do CRM ignora (não vira mensagem duplicada aqui).
 */
import { NextRequest } from 'next/server'
import { and, desc, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadActivities, leads, profiles } from '@/lib/schema'
import { historicoDaNay, instruirANay, marcasDaNay, pararOuDevolverANay } from '@/lib/nayLeitura'

/** O webhook da NAI no n8n da Nay (a mesma porta do fluxo antigo, pela rede interna). */
const WEBHOOK_DA_NAI = process.env.NAI_WEBHOOK_URL || 'http://n8n-viux-n8n-1:5678/webhook/nai-atendimento-locacao'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ telefone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    if (!lead.telefone) return Response.json({ marca: null, historico: [] })
    const [marcas, historico] = await Promise.all([marcasDaNay([lead.telefone]), historicoDaNay(lead.telefone, 80)])
    return Response.json({ marca: marcas.get(lead.telefone) ?? null, historico })
  } catch (err: any) {
    console.error('[leads/nay]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a Nay.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM para ou solta a Nay.')
    const { id } = await params
    const corpo = await req.json().catch(() => ({}))
    const acao = corpo?.acao === 'parar' ? 'parar' : corpo?.acao === 'voltar' ? 'voltar' : corpo?.acao === 'instruir' ? 'instruir' : null
    if (!acao) return apiError(400, 'Ação inválida.')
    const instrucao = String(corpo?.instrucao || '').trim().slice(0, 4000)
    if (acao === 'instruir' && !instrucao) return apiError(400, 'Escreva a instrução antes.')
    const [lead] = await db
      .select({ telefone: leads.phone, titulo: leads.title })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead?.telefone || !/^55\d{10,11}$/.test(lead.telefone)) return apiError(409, 'Esta conversa não tem um telefone que a Nay conheça.')
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const quem = perfil?.nome?.trim() || 'alguém no CRM'

    // 235: "Nay atender com instrução" guarda o recado (48 h) e segue como o "voltar":
    // reentrega o que a pessoa escreveu para a Nay responder agora, já com a instrução
    const r = acao === 'instruir' ? await instruirANay(lead.telefone, instrucao, quem) : await pararOuDevolverANay(lead.telefone, acao, quem)
    if (!r.ok || acao === 'parar') return Response.json({ ...r, reentregou: false }, { status: r.ok ? 200 : 409 })

    // o que a pessoa escreveu depois da nossa última mensagem (até 7 dias; 228: eram
    // 24 h, e quem escreveu ontem de manhã e ficou sem resposta não recebia nada)
    const recentes = await db
      .select({ conteudo: leadActivities.content, metadata: leadActivities.metadata, em: leadActivities.createdAt })
      .from(leadActivities)
      .where(and(eq(leadActivities.leadId, id), eq(leadActivities.type, 'whatsapp')))
      .orderBy(desc(leadActivities.createdAt))
      .limit(40)
    const dela: string[] = []
    let soMidia = 0
    let pulouNossa = false
    for (const a of recentes) {
      const m = (a.metadata || {}) as Record<string, any>
      // com instrução, a Nay responde AGORA: se a última palavra é nossa, pula as nossas
      // e reentrega a última mensagem dela (das últimas 48 h)
      if (m.direction !== 'inbound') { if (acao === 'instruir' && !dela.length) { pulouNossa = true; continue } break }
      if (acao === 'instruir' && pulouNossa && dela.length) break
      if (m.is_reaction || m.deleted) continue
      if (a.em && Date.now() - new Date(a.em).getTime() > (acao === 'instruir' ? 48 : 7 * 24) * 3600_000) break
      const texto = m.media_type === 'audio' ? (m.transcricao || '') : String(a.conteudo || '')
      const limpo = texto && !/^\[(áudio|audio|foto|imagem|vídeo|documento|figurinha)\]$/i.test(texto.trim()) ? texto.trim() : ''
      if (limpo) dela.unshift(limpo)
      else soMidia += 1
    }
    if (!dela.length) {
      return Response.json({
        ...r,
        reentregou: false,
        mensagem: r.mensagem + (soMidia
          ? ' A última mensagem da pessoa é foto, áudio sem transcrição ou arquivo: a Nay não tem texto para responder agora.'
          : ' A última mensagem da conversa é nossa: a Nay responde quando a pessoa escrever.'),
      })
    }

    const aviso = {
      type: 'ReceivedCallback',
      phone: lead.telefone,
      fromMe: false,
      fromApi: false,
      isGroup: false,
      messageId: `CRMNAY${Date.now()}`,
      momment: Date.now(),
      senderName: lead.titulo || lead.telefone,
      chatName: lead.titulo || lead.telefone,
      text: { message: dela.join('\n') },
    }
    // 228: NÃO ESPERA O FLUXO TERMINAR. O webhook da NAI só responde quando a Nay
    // acaba (janela de 25 s + modelo, 30 a 45 s), e os 10 s de antes estouravam:
    // o Tel via "não consegui entregar" com a mensagem já entregue. Agora a entrega
    // segue sozinha (até 2 min) e a tela responde na hora.
    void fetch(WEBHOOK_DA_NAI, {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(aviso), signal: AbortSignal.timeout(120_000),
    }).then((resp) => {
      if (!resp.ok) console.error('[nay voltar] a NAI respondeu', resp.status)
    }).catch((err: any) => {
      console.error('[nay voltar] não reentreguei à NAI', err?.message || err)
    })
    return Response.json({
      ok: true,
      reentregou: true,
      mensagem: `${r.mensagem} A Nay recebeu de novo o que a pessoa escreveu (${dela.length === 1 ? '1 mensagem' : `${dela.length} mensagens`}) e responde em até 1 minuto.`,
    })
  } catch (err: any) {
    console.error('[leads/nay POST]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui falar com a Nay.')
  }
}
