'use client'

/**
 * A BARRA DA PARCERIA, refeita (Pedro, 30/09/2026): "tá muito ruim de ler, muito
 * número, não tá claro nem dividido bem ... algo mais simples visualmente e mais
 * confortável de enxergar, sem muita cor, algo menor".
 *
 * Uma linha fina e neutra, com quatro coisas:
 *   Para responder   conversa FORA da etapa Todos (Visitas, Proprietários, Fechamento,
 *                    Tel, Rayssa) em que a última mensagem é da pessoa -- é o que
 *                    espera gente. Todos é da Nay e não conta ("deve pegar só as
 *                    conversas fora da etapa todos"). Clicar abre a lista.
 *   Visitas hoje · Nay hoje (mensagens dela) · Nay no ar / parada / calada.
 * Saíram a fita correndo, a barra de vida e o pisca. A cor aparece só no número de
 * quem espera: âmbar de 2 a 10, vermelho acima de 10.
 *
 * Os números da Nay vêm de /api/parceria/painel (migração 175).
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { X } from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'
import { formatPhone } from '@/lib/utils'
import { pedeResposta, JANELA_DE_RESPOSTA } from '@/lib/esperaResposta'
import { comAlguemPelaNay, escolhaAMao, etapaDaParceria, ROTULO_DA_ETAPA } from '@/lib/etapaDaParceria'

type PainelDaNay = {
  respostasHoje: number; respostasOntem: number; respostas1h: number; ultimaResposta: string | null
  corretoresHoje: number; corretoresOntem: number; imoveisHoje: number; imoveisOntem: number
  visitasHoje: number; visitasAbertas: number; visitasConfirmadas: number; turnosHoje: number
}

const MINUTO = 60_000
const JANELA = JANELA_DE_RESPOSTA   // 24 h, a mesma das bolinhas das etapas (01/10)
const TOLERANCIA = 2 * MINUTO

/** Onde a conversa está: a etapa, ou com quem (a mesma regra das abas). */
function ondeEsta(lead: LeadWithOwner, marca: MarcaDaNay | undefined): string {
  const aMao = escolhaAMao(lead as any)
  if (aMao === 'tel' || aMao === 'rayssa') return aMao
  if (!aMao && (marca?.telMotivo || '').startsWith('Rayssa:')) return 'rayssa'
  if (!aMao && comAlguemPelaNay(marca)) return 'tel'
  return etapaDaParceria(lead as any, marca)
}

/** Quem espera resposta de GENTE: fora da etapa Todos (a regra da barra). */
export function quemEsperaResposta(leads: LeadWithOwner[], marcas: Record<string, MarcaDaNay>, agora: number) {
  const esperando: Array<{ lead: LeadWithOwner; ha: number; onde: string }> = []
  let chegando = 0
  for (const l of leads) {
    if (l.is_archived || !pedeResposta(l)) continue   // cortesia, reação e o número da Nay não contam
    if (marcas[l.id]?.equipe) continue
    const onde = ondeEsta(l, marcas[l.id])
    if (onde === 'todos') continue                    // Todos é da Nay
    const t = Date.parse(l.last_activity_at || '')
    if (!Number.isFinite(t)) continue
    const ha = agora - t
    if (ha > JANELA) continue
    if (ha < TOLERANCIA) { chegando++; continue }
    esperando.push({ lead: l, ha, onde })
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
  const nivel = n > 10 ? 'alto' : n >= 2 ? 'medio' : 'calmo'
  const p = dados?.painel
  const nay = dados?.nay ?? nayDaLista
  const semResponderHa = p?.ultimaResposta ? agora - Date.parse(p.ultimaResposta) : null
  const nayCalada = !!nay?.ligada && semResponderHa !== null && semResponderHa > 60 * MINUTO && (p?.turnosHoje ?? 0) > 0
  const estadoDaNay = !nay ? '…' : !nay.ligada ? 'Nay parada' : nayCalada ? `Nay calada há ${esperandoHa(semResponderHa!)}` : 'Nay no ar'
  const nayComProblema = !!nay && (!nay.ligada || nayCalada)

  return (
    <div className="barra-calma" aria-label="Números da Parceria">
      <div ref={caixa} className="relative flex">
        <button type="button" onClick={() => setListaAberta((v) => !v)} aria-expanded={listaAberta}
                className={`barra-calma__item barra-calma__item--botao barra-calma__item--${nivel}`}
                title={esperando[0] ? `Fora da etapa Todos, esperando resposta de gente. A mais antiga espera há ${esperandoHa(esperando[0].ha)}. Clique para ver.` : 'Ninguém fora da etapa Todos esperando resposta'}>
          <span className="barra-calma__rotulo">Para responder</span>
          <span className="barra-calma__valor">{n}</span>
        </button>

        {listaAberta && (
          <div className="painel-barra__lista wa-rolagem" role="dialog" aria-label="Quem está esperando resposta">
            <div className="flex items-center justify-between px-3 pt-2 pb-1">
              <span className="text-[12.5px] font-semibold" style={{ color: 'var(--wa-text-2)' }}>
                Esperando resposta, fora de Todos{chegando ? ` · ${chegando} chegando agora` : ''}
              </span>
              <button type="button" onClick={() => setListaAberta(false)} aria-label="Fechar" className="p-1 rounded-full hover:bg-[var(--wa-row-hover)]">
                <X size={16} style={{ color: 'var(--wa-text-2)' }} />
              </button>
            </div>
            {esperando.length === 0 ? (
              <p className="text-[14px] px-3 py-4" style={{ color: 'var(--wa-text-2)' }}>Ninguém esperando resposta.</p>
            ) : (
              <ul className="flex flex-col px-1 pb-1">
                {esperando.slice(0, 60).map(({ lead, ha, onde }) => (
                  <li key={lead.id}>
                    <button type="button" onClick={() => { setListaAberta(false); aoAbrirConversa(lead.id) }} className="painel-espera">
                      <span className="painel-espera__tempo" style={{ color: 'var(--wa-text-2)' }}>{esperandoHa(ha)}</span>
                      <span className="min-w-0 flex-1 text-left">
                        <span className="block text-[14px] font-medium truncate" style={{ color: 'var(--wa-text)' }}>
                          {formatPhone(lead.title)}
                          <span className="wa-marca ml-2" style={{ color: 'var(--wa-text-2)' }}>{(ROTULO_DA_ETAPA as Record<string, string>)[onde] || onde}</span>
                        </span>
                        <span className="block text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>{lead.last_message_content || '…'}</span>
                      </span>
                      <span className="painel-espera__responder">Responder</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        )}
      </div>

      <div className="barra-calma__item" title="Visitas marcadas para hoje">
        <span className="barra-calma__rotulo">Visitas hoje</span>
        <span className="barra-calma__valor">{p ? p.visitasHoje : '…'}</span>
      </div>
      <div className="barra-calma__item" title={p ? `Mensagens que a Nay mandou hoje (ontem: ${p.respostasOntem}). Corretores atendidos hoje: ${p.corretoresHoje}.` : ''}>
        <span className="barra-calma__rotulo">Nay hoje</span>
        <span className="barra-calma__valor">{p ? p.respostasHoje : '…'}</span>
      </div>
      <div className={`barra-calma__item ${nayComProblema ? 'barra-calma__item--alto' : ''}`}
           title={nay && !nay.ligada ? (nay.motivo || 'A Nay está parada') : nayCalada ? 'A Nay não responde há mais de 1 hora (crédito da OpenAI, erro no n8n)' : 'A Nay está atendendo'}>
        <span className={`barra-calma__luz ${nayComProblema ? 'barra-calma__luz--ruim' : ''}`} />
        <span className="barra-calma__rotulo">{estadoDaNay}</span>
      </div>
    </div>
  )
}
