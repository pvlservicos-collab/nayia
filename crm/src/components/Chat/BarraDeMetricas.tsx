'use client'

/**
 * A BARRA DE MÉTRICAS DA PARCERIA (Pedro, 29/09/2026): "um painel de métricas e
 * alertas de notificação estilo bolsa de valores. Um alerta bem grande PESSOAS
 * PARA RESPONDER XX e um triângulo piscando ... uma barrinha: acima de 10
 * pessoas ela pisca em vermelho, 5 amarelo, menos de 2 verde ... a cada 10
 * pessoas uma linha preta ... quero algo meio jogo mesmo. Lá em cima: visitas
 * agendadas, Nay respondendo tanto, mas principalmente um destaque em pessoas a
 * responder".
 *
 * E em seguida: "não era uma aba métricas, era uma barra fixa de métricas com
 * os números, ocupando do lado da agenda até o canto direito da tela, mostrando
 * enquanto eu tô no chat ou na agenda". Por isso ela mora na faixa das abas,
 * depois de "Visitas agendadas", e vale nas duas. Clicar no número abre a lista
 * de quem espera, para responder dali.
 *
 * PESSOAS PARA RESPONDER = conversa da Parceria em que a última mensagem é da
 * pessoa (reação não conta), nas últimas 24 h, há mais de 2 min (a Nay costuma
 * responder em segundos: quem passou disso ficou sem resposta), e que não é da
 * equipe. Verde até 1, amarelo de 2 a 10, vermelho piscando acima de 10.
 * Os números da Nay vêm de /api/parceria/painel (migração 175).
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { Warning, CheckCircle, ArrowUp, ArrowDown, Robot, CalendarCheck, X } from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'
import { formatPhone } from '@/lib/utils'

type PainelDaNay = {
  respostasHoje: number; respostasOntem: number; respostas1h: number; ultimaResposta: string | null
  corretoresHoje: number; corretoresOntem: number; imoveisHoje: number; imoveisOntem: number
  visitasHoje: number; visitasAbertas: number; visitasConfirmadas: number; turnosHoje: number
}

const MINUTO = 60_000
const JANELA = 24 * 60 * MINUTO
const TOLERANCIA = 2 * MINUTO

/** Quem espera resposta (a regra da barra). */
export function quemEsperaResposta(leads: LeadWithOwner[], marcas: Record<string, MarcaDaNay>, agora: number) {
  const esperando: Array<{ lead: LeadWithOwner; ha: number }> = []
  let chegando = 0
  for (const l of leads) {
    if (l.is_archived || l.last_message_sender_type !== 'lead') continue
    if (String(l.last_message_content || '').startsWith('Reagiu com')) continue
    if (marcas[l.id]?.equipe) continue
    const t = Date.parse(l.last_activity_at || '')
    if (!Number.isFinite(t)) continue
    const ha = agora - t
    if (ha > JANELA) continue
    if (ha < TOLERANCIA) { chegando++; continue }
    esperando.push({ lead: l, ha })
  }
  esperando.sort((a, b) => b.ha - a.ha)
  return { esperando, chegando }
}

function esperandoHa(ms: number) {
  const min = Math.floor(ms / MINUTO)
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  return `${h}h${String(min % 60).padStart(2, '0')}`
}

function Variacao({ hoje, ontem }: { hoje: number; ontem: number }) {
  if (!ontem && !hoje) return <span className="painel-var painel-var--igual">—</span>
  if (!ontem) return <span className="painel-var painel-var--sobe"><ArrowUp size={11} weight="bold" />novo</span>
  const pct = Math.round(((hoje - ontem) / ontem) * 100)
  if (pct === 0) return <span className="painel-var painel-var--igual">= ontem</span>
  return pct > 0
    ? <span className="painel-var painel-var--sobe"><ArrowUp size={11} weight="bold" />{pct}%</span>
    : <span className="painel-var painel-var--desce"><ArrowDown size={11} weight="bold" />{Math.abs(pct)}%</span>
}

/** A barra de vida: um gomo por pessoa, um risco preto a cada 10. */
function BarraDeVida({ n, nivel }: { n: number; nivel: 'verde' | 'amarelo' | 'vermelho' }) {
  const capacidade = Math.max(30, Math.ceil((n + 1) / 10) * 10)
  const blocos = Array.from({ length: capacidade / 10 }, (_, b) => b)
  return (
    <div className={`painel-vida painel-vida--${nivel}`} role="meter" aria-valuemin={0} aria-valuemax={capacidade} aria-valuenow={n}
         aria-label={`${n} pessoas para responder`} title={`${n} de ${capacidade} · um risco preto a cada 10`}>
      {blocos.map((b) => (
        <div key={b} className="painel-vida__bloco">
          {Array.from({ length: 10 }, (_, i) => b * 10 + i).map((k) => (
            <span key={k} className={`painel-vida__gomo ${k < n ? 'painel-vida__gomo--cheio' : ''}`} />
          ))}
        </div>
      ))}
    </div>
  )
}

export default function BarraDeMetricas({ leads, marcas, nay: nayDaLista, aoAbrirConversa }: {
  leads: LeadWithOwner[]
  marcas: Record<string, MarcaDaNay>
  nay: EstadoDaNay | null
  aoAbrirConversa: (leadId: string) => void
}) {
  const [agora, setAgora] = useState(() => Date.now())
  const [dados, setDados] = useState<{ painel: PainelDaNay; nay: EstadoDaNay } | null>(null)
  const [listaAberta, setListaAberta] = useState(false)
  const caixa = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const t = setInterval(() => setAgora(Date.now()), 15_000)
    return () => clearInterval(t)
  }, [])
  useEffect(() => {
    let vivo = true
    const ler = async () => {
      try {
        const r = await fetch('/api/parceria/painel')
        const j = await r.json()
        if (r.ok && vivo) setDados(j)
      } catch { /* a barra segue com os números da lista */ }
    }
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [])
  // a lista fecha com clique fora ou Esc
  useEffect(() => {
    if (!listaAberta) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setListaAberta(false) }
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setListaAberta(false) }
    document.addEventListener('mousedown', fora)
    document.addEventListener('keydown', esc)
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc) }
  }, [listaAberta])

  const { esperando, chegando } = useMemo(() => quemEsperaResposta(leads, marcas, agora), [leads, marcas, agora])

  const n = esperando.length
  const nivel: 'verde' | 'amarelo' | 'vermelho' = n > 10 ? 'vermelho' : n >= 2 ? 'amarelo' : 'verde'
  const p = dados?.painel
  const nay = dados?.nay ?? nayDaLista
  const telAtendendo = Object.values(marcas).filter((m) => m.telAtendendo).length
  const semResponderHa = p?.ultimaResposta ? agora - Date.parse(p.ultimaResposta) : null
  const nayCalada = n > 0 && semResponderHa !== null && semResponderHa > 15 * MINUTO
  const estadoDaNay = !nay ? '…' : nay.ligada ? (nayCalada ? `CALADA HÁ ${esperandoHa(semResponderHa!)}` : 'NO AR') : 'PARADA'
  const nayComProblema = !!nay && (!nay.ligada || nayCalada)

  // a fita corre com o que não está fixo na barra
  const fita: Array<{ rotulo: string; valor: string; extra?: React.ReactNode; soEstreito?: boolean }> = p ? [
    // em tela estreita os placares fixos somem e estes dois vão para a fita
    { rotulo: 'VISITAS HOJE', valor: String(p.visitasHoje), soEstreito: true },
    { rotulo: 'NAY HOJE', valor: String(p.respostasHoje), extra: <Variacao hoje={p.respostasHoje} ontem={p.respostasOntem} />, soEstreito: true },
    { rotulo: 'NA ÚLTIMA HORA', valor: String(p.respostas1h) },
    { rotulo: 'CORRETORES ATENDIDOS', valor: String(p.corretoresHoje), extra: <Variacao hoje={p.corretoresHoje} ontem={p.corretoresOntem} /> },
    { rotulo: 'IMÓVEIS ENVIADOS', valor: String(p.imoveisHoje), extra: <Variacao hoje={p.imoveisHoje} ontem={p.imoveisOntem} /> },
    { rotulo: 'PERGUNTAS', valor: String(p.turnosHoje) },
    { rotulo: 'VISITAS EM ANDAMENTO', valor: String(p.visitasAbertas) },
    { rotulo: 'CONFIRMADAS', valor: String(p.visitasConfirmadas) },
    { rotulo: 'TEL ATENDENDO', valor: String(telAtendendo) },
    ...(chegando ? [{ rotulo: 'CHEGANDO AGORA', valor: String(chegando) }] : []),
  ] : [{ rotulo: 'TEL ATENDENDO', valor: String(telAtendendo) }]

  return (
    <div className="painel-barra" aria-label="Métricas da Parceria">
      {/* o destaque: pessoas para responder */}
      <div ref={caixa} className="relative flex-shrink-0 flex">
        <button type="button" onClick={() => setListaAberta((v) => !v)} aria-expanded={listaAberta}
                className={`painel-barra__alerta painel-barra__alerta--${nivel}`}
                title={esperando[0] ? `A mais antiga espera há ${esperandoHa(esperando[0].ha)}. Clique para ver quem é.` : 'Ninguém esperando resposta'}>
          {nivel === 'verde'
            ? <CheckCircle size={22} weight="fill" className="painel-barra__icone" />
            : <Warning size={22} weight="fill" className="painel-barra__icone painel-barra__icone--pisca" />}
          <span className="painel-barra__numero">{n}</span>
          <span className="painel-barra__rotulo">Pessoas para<br />responder</span>
        </button>

        {listaAberta && (
          <div className="painel-barra__lista wa-rolagem" role="dialog" aria-label="Quem está esperando resposta">
            <div className="flex items-center justify-between px-3 pt-2 pb-1">
              <span className="text-[12.5px] font-bold tracking-wide uppercase" style={{ color: 'var(--wa-text-2)' }}>
                Quem está esperando{chegando ? ` · ${chegando} chegando agora` : ''}
              </span>
              <button type="button" onClick={() => setListaAberta(false)} aria-label="Fechar" className="p-1 rounded-full hover:bg-[var(--wa-row-hover)]">
                <X size={16} style={{ color: 'var(--wa-text-2)' }} />
              </button>
            </div>
            {esperando.length === 0 ? (
              <p className="text-[14px] px-3 py-4" style={{ color: 'var(--wa-text-2)' }}>Ninguém esperando resposta. 🎉</p>
            ) : (
              <ul className="flex flex-col px-1 pb-1">
                {esperando.slice(0, 60).map(({ lead, ha }) => {
                  const m = marcas[lead.id]
                  const tom = ha > 60 * MINUTO ? 'vermelho' : ha > 15 * MINUTO ? 'amarelo' : 'verde'
                  return (
                    <li key={lead.id}>
                      <button type="button" onClick={() => { setListaAberta(false); aoAbrirConversa(lead.id) }} className="painel-espera">
                        <span className={`painel-espera__tempo painel-espera__tempo--${tom}`}>{esperandoHa(ha)}</span>
                        <span className="min-w-0 flex-1 text-left">
                          <span className="block text-[14px] font-medium truncate" style={{ color: 'var(--wa-text)' }}>
                            {formatPhone(lead.title)}
                            {m?.telAtendendo && <span className="wa-marca ml-2" style={{ color: 'var(--wa-tag-tel)' }}>Tel</span>}
                            {m?.corretor && <span className="wa-marca ml-2" style={{ color: 'var(--wa-tag-corretor)' }}>Corretor</span>}
                            {m?.proprietario && <span className="wa-marca ml-2" style={{ color: 'var(--wa-tag-prop)' }}>Proprietário</span>}
                          </span>
                          <span className="block text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>{lead.last_message_content || '…'}</span>
                        </span>
                        <span className="painel-espera__responder">Responder</span>
                      </button>
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        )}
      </div>

      {/* a barra de vida */}
      <div className="painel-barra__vida"><BarraDeVida n={n} nivel={nivel} /></div>

      {/* os placares fixos */}
      <div className="painel-barra__placar painel-barra__placar--largo" title="Visitas marcadas para hoje">
        <CalendarCheck size={16} weight="fill" />
        <span className="painel-barra__placar-rotulo">VISITAS HOJE</span>
        <span className="painel-barra__placar-valor">{p ? p.visitasHoje : '…'}</span>
      </div>
      <div className="painel-barra__placar painel-barra__placar--largo" title="Mensagens que a Nay mandou hoje, contra ontem">
        <Robot size={16} weight="fill" />
        <span className="painel-barra__placar-rotulo">NAY HOJE</span>
        <span className="painel-barra__placar-valor">{p ? p.respostasHoje : '…'}</span>
        {p && <Variacao hoje={p.respostasHoje} ontem={p.respostasOntem} />}
      </div>
      <div className={`painel-barra__placar ${nayComProblema ? 'painel-barra__placar--alerta' : ''}`}
           title={nay && !nay.ligada ? (nay.motivo || 'A Nay está parada') : nayCalada ? 'Tem gente esperando e a Nay não responde há mais de 15 min (crédito da OpenAI, erro no n8n)' : 'A Nay está atendendo'}>
        <span className={`painel-barra__luz ${nayComProblema ? 'painel-barra__luz--vermelha' : 'painel-barra__luz--verde'}`} />
        <span className="painel-barra__placar-valor painel-barra__placar-valor--texto">{estadoDaNay}</span>
      </div>

      {/* a fita da bolsa, até o canto direito */}
      <div className="painel-fita painel-barra__fita" aria-label="Números de hoje">
        <div className="painel-fita__trilho">
          {[0, 1].map((copia) => (
            <div key={copia} className="painel-fita__volta" aria-hidden={copia === 1}>
              {fita.map((it, i) => (
                <span key={i} className={`painel-fita__item ${it.soEstreito ? 'painel-fita__item--so-estreito' : ''}`}>
                  <span className="painel-fita__rotulo">{it.rotulo}</span>
                  <span className="painel-fita__valor">{it.valor}</span>
                  {it.extra}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
