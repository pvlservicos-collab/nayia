'use client'

/**
 * OS AGENTES NO CARD DO LEAD (Pedro, 24/10/2026, linha WhatsApp Leads): "uma legenda de cores para cada agente visível no
 * card do lead" e "um histórico de atendimento em cada card do lead, mostrando em tags cada agente que ativou incluindo se
 * um humano assumiu". Lê /api/leads/{id}/agentes (os eventos do banco da Nay + a equipe pelo CRM). Etiqueta tracejada =
 * o agente decidiu em sombra (não valeu).
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { CaretDown, CaretRight } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS as fusoDeManaus } from '@/lib/fusoDeManaus'
import { rotuloDaAcao, type Agente, type EventoDeAgente, type ModoDosAgentes } from '@/lib/agentes'

const MOSTRA = 24

function dia(iso: string): string {
  return new Date(iso).toLocaleDateString('pt-BR', { timeZone: fusoDeManaus, day: '2-digit', month: '2-digit' })
}
function hora(iso: string): string {
  return new Date(iso).toLocaleTimeString('pt-BR', { timeZone: fusoDeManaus, hour: '2-digit', minute: '2-digit' })
}

export function Legenda({ agentes }: { agentes: Agente[] }) {
  return (
    <div className="flex flex-wrap gap-x-3 gap-y-1.5">
      {agentes.map((a) => (
        <span key={a.chave} className="inline-flex items-center gap-1.5 text-[12px]" style={{ color: 'var(--wa-text)' }} title={a.descricao}>
          <i className="inline-block w-2.5 h-2.5 rounded-full" style={{ background: a.cor }} />{a.nome}
        </span>
      ))}
    </div>
  )
}

export function EtiquetaDeAgente({ e }: { e: EventoDeAgente }) {
  const sombra = e.modo === 'sombra'
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-[3px] text-[11.5px] font-medium leading-none whitespace-nowrap"
      style={{
        background: `color-mix(in srgb, ${e.cor} ${sombra ? 6 : 14}%, transparent)`,
        border: `1px ${sombra ? 'dashed' : 'solid'} color-mix(in srgb, ${e.cor} 55%, transparent)`,
        color: 'var(--wa-text)',
      }}
      title={`${e.nome}: ${rotuloDaAcao(e.acao)}${e.detalhe ? ` — ${e.detalhe}` : ''}${sombra ? ' (sombra: não valeu)' : ''}`}
    >
      <i className="inline-block w-2 h-2 rounded-full" style={{ background: e.cor }} />
      {e.nome}
      <span style={{ color: 'var(--wa-text-2)' }}>{hora(e.em)}</span>
    </span>
  )
}

export default function AgentesDoLead({ leadId }: { leadId: string }) {
  const [dados, setDados] = useState<{ modo: ModoDosAgentes; agentes: Agente[]; eventos: EventoDeAgente[] } | null>(null)
  const [tudo, setTudo] = useState(false)
  const [aberto, setAberto] = useState(false)

  const ler = useCallback(async () => {
    try {
      const r = await fetch(`/api/leads/${leadId}/agentes`)
      if (r.ok) setDados(await r.json())
    } catch { /* o histórico fica como estava */ }
  }, [leadId])

  useEffect(() => { setDados(null); setTudo(false); setAberto(false); void ler() }, [ler])

  const porDia = useMemo(() => {
    const lista = (dados?.eventos || []).slice(0, tudo ? undefined : MOSTRA)
    const grupos: { dia: string; eventos: EventoDeAgente[] }[] = []
    for (const e of lista) {
      const d = dia(e.em)
      if (!grupos.length || grupos[grupos.length - 1].dia !== d) grupos.push({ dia: d, eventos: [] })
      grupos[grupos.length - 1].eventos.push(e)
    }
    return grupos
  }, [dados, tudo])

  // 02/11 (Pedro: "retira isso Agentes da Nay ligado desse card lateral, eu já sei como funciona" e "diminui a Histórico de
  // atendimento"): sem o título, o "ligado" e a legenda de cores; o histórico fica numa linha e abre ao clicar.
  const total = dados?.eventos.length ?? 0
  return (
    <section className="px-4 py-2" style={{ background: 'var(--wa-panel)' }}>
      <button type="button" onClick={() => setAberto((a) => !a)} aria-expanded={aberto}
              className="w-full flex items-center gap-1.5 py-1 text-left text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
        {aberto ? <CaretDown size={12} /> : <CaretRight size={12} />}
        <span className="flex-1">Histórico de atendimento</span>
        {dados && <span className="rounded-full px-1.5 text-[11px]" style={{ background: 'var(--wa-row-selected)' }}>{total}</span>}
      </button>
      {aberto && (!dados ? (
        <p className="text-[11.5px] mt-1" style={{ color: 'var(--wa-text-2)' }}>Carregando…</p>
      ) : !dados.eventos.length ? (
        <p className="text-[11.5px] mt-1" style={{ color: 'var(--wa-text-2)' }}>Nenhum agente ativou nesta conversa ainda.</p>
      ) : (
        <div className="flex flex-col gap-1.5 mt-1 max-h-[220px] overflow-y-auto wa-rolagem">
          {porDia.map((g) => (
            <div key={g.dia}>
              <p className="text-[10.5px] mb-0.5" style={{ color: 'var(--wa-text-2)' }}>{g.dia}</p>
              <div className="flex flex-wrap gap-1">
                {g.eventos.map((e, i) => <EtiquetaDeAgente key={`${e.em}-${e.agente}-${i}`} e={e} />)}
              </div>
            </div>
          ))}
          {dados.eventos.length > MOSTRA && (
            <button type="button" onClick={() => setTudo(!tudo)} className="self-start text-[11.5px] font-semibold" style={{ color: 'var(--wa-green)' }}>
              {tudo ? 'Mostrar menos' : `Ver todos (${dados.eventos.length})`}
            </button>
          )}
        </div>
      ))}
    </section>
  )
}
