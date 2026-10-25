'use client'

/**
 * OS AGENTES NO CARD DO LEAD (Pedro, 24/10/2026, linha WhatsApp Leads): "uma legenda de cores para cada agente visível no
 * card do lead" e "um histórico de atendimento em cada card do lead, mostrando em tags cada agente que ativou incluindo se
 * um humano assumiu". Lê /api/leads/{id}/agentes (os eventos do banco da Nay + a equipe pelo CRM). Etiqueta tracejada =
 * o agente decidiu em sombra (não valeu).
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowsClockwise, CircleNotch } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS as fusoDeManaus } from '@/lib/fusoDeManaus'
import { ROTULO_DO_MODO, rotuloDaAcao, type Agente, type EventoDeAgente, type ModoDosAgentes } from '@/lib/agentes'

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
  const [carregando, setCarregando] = useState(false)
  const [tudo, setTudo] = useState(false)

  const ler = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/leads/${leadId}/agentes`)
      if (r.ok) setDados(await r.json())
    } finally {
      setCarregando(false)
    }
  }, [leadId])

  useEffect(() => { setDados(null); setTudo(false); void ler() }, [ler])

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

  return (
    <section className="px-4 py-3.5" style={{ background: 'var(--wa-panel)' }}>
      <div className="flex items-center justify-between gap-2 mb-2">
        <h3 className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
          Agentes da Nay
          {dados && (
            <span className="ml-1.5 text-[11px] px-1.5 py-[1px] rounded-full"
                  style={{ background: dados.modo === 'sim' ? 'color-mix(in srgb, var(--wa-green) 18%, transparent)' : 'var(--wa-row-selected)' }}
                  title={ROTULO_DO_MODO[dados.modo]}>
              {dados.modo === 'sim' ? 'ligado' : dados.modo === 'sombra' ? 'sombra' : 'desligado'}
            </span>
          )}
        </h3>
        <button type="button" onClick={() => void ler()} className="p-1 rounded" title="Atualizar" style={{ color: 'var(--wa-text-2)' }}>
          {carregando ? <CircleNotch size={15} className="animate-spin" /> : <ArrowsClockwise size={15} />}
        </button>
      </div>

      {dados && <Legenda agentes={dados.agentes.filter((a) => a.chave !== 'fluxo')} />}

      <p className="text-[12px] mt-3 mb-1.5" style={{ color: 'var(--wa-text-2)' }}>Histórico de atendimento</p>
      {!dados ? (
        <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Carregando…</p>
      ) : !dados.eventos.length ? (
        <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Nenhum agente ativou nesta conversa ainda.</p>
      ) : (
        <div className="flex flex-col gap-2">
          {porDia.map((g) => (
            <div key={g.dia}>
              <p className="text-[11px] mb-1" style={{ color: 'var(--wa-text-2)' }}>{g.dia}</p>
              <div className="flex flex-wrap gap-1.5">
                {g.eventos.map((e, i) => <EtiquetaDeAgente key={`${e.em}-${e.agente}-${i}`} e={e} />)}
              </div>
            </div>
          ))}
          {dados.eventos.length > MOSTRA && (
            <button type="button" onClick={() => setTudo(!tudo)} className="self-start text-[12px] font-semibold" style={{ color: 'var(--wa-green)' }}>
              {tudo ? 'Mostrar menos' : `Ver todos (${dados.eventos.length})`}
            </button>
          )}
        </div>
      )}
    </section>
  )
}
