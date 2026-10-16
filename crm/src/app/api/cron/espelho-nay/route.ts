/**
 * POST /api/cron/espelho-nay -- a conferência com a Nay (ver src/lib/espelhoDaNay.ts).
 *
 * Chamada a cada minuto pelo cron do servidor (/etc/cron.d/crm-espelho-nay),
 * de dentro do próprio container, com o cabeçalho `x-cron-segredo` =
 * CRON_SEGREDO do .env. Sem ele, 401 -- o middleware deixa a rota passar
 * justamente porque quem confere é ela.
 *
 * Sem parâmetros, olha dos últimos 40 minutos até 40 segundos atrás (sobra de
 * sobra para o que o espelho perder enquanto o CRM reinicia). Os 40 s são do
 * espelho do n8n, que entrega em ~30 s quando a IA anda (eram 2 min até 29/09;
 * com a IA falhando o espelho nem roda, e a mensagem esperava 2 a 4 min). O que
 * a conferência traz ao vivo ganha "não lida", desarquiva e notifica, como o
 * espelho; o índice único do id da Z-API impede cópia. `?desde=...&ate=...` (ISO) confere
 * um intervalo qualquer, até 3 dias por chamada, como histórico (sem acordar
 * conversa) -- é assim que o que faltava desde 25/09 foi trazido.
 */
import { NextRequest, after } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { conferirACaptacao, conferirComANay } from '@/lib/espelhoDaNay'
import { refazerTranscricoesQueFalharam } from '@/lib/transcricao'
import { realinharUltimaMensagem } from '@/lib/realinharUltimaMensagem'
import { marcarOrganicos } from '@/lib/tagOrganico'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 300

function segredoConfere(veio: string | null): boolean {
  const certo = process.env.CRON_SEGREDO || ''
  if (!certo || !veio) return false
  const a = Buffer.from(certo)
  const b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

export async function POST(req: NextRequest) {
  if (!segredoConfere(req.headers.get('x-cron-segredo'))) return new Response('não autorizado', { status: 401 })

  const [parceria] = await db
    .select({ org: integrations.organizationId })
    .from(integrations)
    .where(and(eq(integrations.type, 'whatsapp_zapi'), isNull(integrations.deletedAt)))
    .limit(1)
  if (!parceria) return Response.json({ erro: 'sem a linha da Parceria' }, { status: 404 })

  const agora = Date.now()
  const desdeTexto = req.nextUrl.searchParams.get('desde')
  const ateTexto = req.nextUrl.searchParams.get('ate')
  // 40 s (29/09; eram 2 min): o espelho do n8n entrega em ~30 s quando a IA
  // anda; quando ela falha (OpenAI sem crédito) ele nem roda, e a mensagem
  // esperava a conferência 2 a 4 min (42% das recebidas numa tarde)
  /*
   * A RODADA RÁPIDA (`?rapida=1`, 29/09, Pedro: "preciso do máximo de
   * velocidade nas mensagens no CRM, mostra logo"): a cada 10 s, os últimos 3
   * minutos até 8 s atrás. O registro da Nay grava a mensagem assim que ela
   * chega (antes da janela de 20 s e da IA), então a conversa aparece aqui em
   * ~10-18 s mesmo quando o espelho do n8n demora ou não roda. A de minuto
   * continua com a janela larga, para o que a rápida perder.
   */
  const rapida = req.nextUrl.searchParams.get('rapida') === '1'
  const ate = ateTexto ? new Date(ateTexto) : new Date(agora - (rapida ? 8_000 : 40_000))
  const desde = desdeTexto ? new Date(desdeTexto) : new Date(agora - (rapida ? 3 * 60_000 : 40 * 60_000))
  const historico = !!(desdeTexto || ateTexto)
  if (isNaN(desde.getTime()) || isNaN(ate.getTime()) || desde >= ate) {
    return Response.json({ erro: 'intervalo inválido' }, { status: 400 })
  }
  if (ate.getTime() - desde.getTime() > 3 * 24 * 3600_000) {
    return Response.json({ erro: 'no máximo 3 dias por chamada' }, { status: 400 })
  }

  try {
    // a transcrição que falhou de passagem (OpenAI sem crédito), a cada minuto
    if (!historico && !rapida) {
      after(() => refazerTranscricoesQueFalharam()
        .then((t) => { if (t.tentadas) console.log('[transcricao] refeitas', JSON.stringify(t)) })
        .catch((e) => console.error('[transcricao] rodada', e?.message || e)))
    }
    const resultado = await conferirComANay(parceria.org, desde, ate, { aoVivo: !historico })
    /* E O RESUMO DA CONVERSA (30/09): depois de trazer o que faltava, acerta
       "quem falou por último" onde ele discorda das mensagens de verdade. É o
       que faz a barra de "pessoas para responder" baixar quando a resposta foi
       dada pelo celular. Só na rodada de minuto, e nunca derruba a rota. */
    if (!historico && !rapida) {
      after(() => realinharUltimaMensagem(parceria.org)
        .then((n) => { if (n) console.log('[resumo da conversa] realinhadas', n) })
        .catch((e) => console.error('[resumo da conversa] falhou', e?.message || e)))
    }
    // e a captação (29/09): o mesmo intervalo, na linha dela
    const captacao = await conferirACaptacao(parceria.org, desde, ate, { aoVivo: !historico })
    // 390 (16/10): quem a Nay do WhatsApp atende como orgânico ganha a tag "Orgânico" (depois da conferência,
    // que é quem cria a conversa)
    if (!historico && !rapida) {
      after(() => marcarOrganicos(parceria.org)
        .then((n) => { if (n) console.log('[orgânico] marcadas', n) })
        .catch((e) => console.error('[orgânico] falhou', e?.message || e)))
    }
    if (captacao && (captacao.trazidas || captacao.erros)) console.log('[conferência da captação]', JSON.stringify(captacao))
    if (!resultado) return Response.json({ ocupado: true, captacao }, { status: 202 })
    if (resultado.trazidas || resultado.erros) console.log('[espelho da Nay]', JSON.stringify(resultado))
    return Response.json({ ...resultado, captacao })
  } catch (err: any) {
    console.error('[espelho da Nay] falhou', err?.message || err)
    return Response.json({ erro: err?.message || 'falhou' }, { status: 500 })
  }
}
