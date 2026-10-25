'use client'

/**
 * O REGISTRO DE FLUXOS DA NAY LEADS (Pedro, 25/10/2026: "deixe lá onde tem o fluxo um registro de fluxos, onde a nay passou
 * e quais ferramentas passou, tipo um log de traços"). Embaixo do fluxograma da aba Arquitetura: cada turno (a mensagem do
 * cliente até a resposta) numa linha, com a corrente dos passos (Fluxo, Mestre, Atendimento, Imóveis...) nas cores dos
 * agentes; aberto, cada passo com a hora, o tempo, os tokens, o custo, o erro e o detalhe inteiro.
 * GET /api/agentes/tracos (nayia 490: crm_agentes_tracos).
 */
import { useCallback, useEffect, useState } from 'react'
import { ArrowsClockwise, CaretDown, CaretRight, CircleNotch, MagnifyingGlass, Warning } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS } from '@/lib/fusoDeManaus'
import { rotuloDaAcao, type PassoDoTraco, type TurnoDoTraco } from '@/lib/agentes'

const PAGINA = 30

function hora(iso: string, comDia = true) {
  return new Date(iso).toLocaleString('pt-BR', {
    timeZone: FUSO_DE_MANAUS, ...(comDia ? { day: '2-digit', month: '2-digit' } : {}), hour: '2-digit', minute: '2-digit', second: '2-digit',
  })
}
function segundos(ms: number | null | undefined) {
  if (ms == null) return ''
  return ms < 1000 ? `${ms} ms` : `${(ms / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} s`
}
function quem(t: TurnoDoTraco) {
  const fone = (t.telefone || t.chave8 || '').replace(/\D/g, '')
  const fim = fone ? `…${fone.slice(-4)}` : ''
  return [t.nome, fim].filter(Boolean).join(' ') || 'sem lead'
}

function Elo({ p }: { p: PassoDoTraco }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full px-2 py-[3px] text-[11.5px] leading-none whitespace-nowrap"
          title={`${p.nome}: ${rotuloDaAcao(p.acao)}${p.resumo ? ` — ${p.resumo}` : ''}`}
          style={{ background: `color-mix(in srgb, ${p.cor} ${p.modo === 'sombra' ? 6 : 14}%, transparent)`,
                   border: `1px ${p.modo === 'sombra' ? 'dashed' : 'solid'} ${p.erro ? '#DC2626' : `color-mix(in srgb, ${p.cor} 55%, transparent)`}`,
                   color: 'var(--wa-text)' }}>
      <i className="inline-block w-2 h-2 rounded-full" style={{ background: p.cor }} />
      <b className="font-medium">{p.nome}</b>
      <span style={{ color: 'var(--wa-text-2)' }}>{rotuloDaAcao(p.acao)}</span>
      {p.ms != null && <span style={{ color: 'var(--wa-text-2)' }}>· {segundos(p.ms)}</span>}
      {p.erro && <Warning size={12} weight="fill" color="#DC2626" />}
    </span>
  )
}

function Passo({ p, inicio }: { p: PassoDoTraco; inicio: string }) {
  const [aberto, setAberto] = useState(false)
  const desde = new Date(p.em).getTime() - new Date(inicio).getTime()
  const detalhe = Object.fromEntries(Object.entries(p.detalhe || {}).filter(([k]) => k !== 'resumo'))
  return (
    <div className="flex gap-3 text-[12.5px]">
      <div className="flex flex-col items-center">
        <i className="inline-block w-2.5 h-2.5 rounded-full mt-1" style={{ background: p.cor }} />
        <div className="flex-1 w-px" style={{ background: 'var(--wa-divider)' }} />
      </div>
      <div className="flex-1 min-w-0 pb-2.5">
        <div className="flex flex-wrap items-baseline gap-x-2">
          <span className="tabular-nums" style={{ color: 'var(--wa-text-2)' }}>+{segundos(Math.max(0, desde)) || '0 ms'}</span>
          <b style={{ color: p.cor }}>{p.nome}</b>
          <span style={{ color: 'var(--wa-text)' }}>{rotuloDaAcao(p.acao)}</span>
          <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>
            {[p.ms != null && `tempo ${segundos(p.ms)}`, p.tokens > 0 && `${p.tokens.toLocaleString('pt-BR')} tokens`,
              p.custo_usd ? `US$ ${Number(p.custo_usd).toLocaleString('pt-BR', { maximumFractionDigits: 5 })}` : '',
              p.modelo, p.modo === 'sombra' && 'sombra'].filter(Boolean).join(' · ')}
          </span>
        </div>
        {p.resumo && <p className="break-words" style={{ color: 'var(--wa-text)' }}>{p.resumo}</p>}
        {p.erro && <p className="break-words" style={{ color: '#DC2626' }}>Erro: {p.erro}</p>}
        {Object.keys(detalhe).length > 0 && (
          <button type="button" onClick={() => setAberto((x) => !x)} className="text-[11.5px] mt-0.5" style={{ color: 'var(--wa-text-2)' }}>
            {aberto ? 'esconder o detalhe' : 'ver o detalhe'}
          </button>
        )}
        {aberto && (
          <pre className="mt-1 p-2 rounded text-[11px] leading-4 whitespace-pre-wrap break-words max-h-64 overflow-auto"
               style={{ background: 'var(--wa-row-hover)', color: 'var(--wa-text)' }}>{JSON.stringify(detalhe, null, 2)}</pre>
        )}
      </div>
    </div>
  )
}

function Turno({ t }: { t: TurnoDoTraco }) {
  const [aberto, setAberto] = useState(false)
  return (
    <div className="rounded-lg" style={{ border: `1px solid ${t.erros ? '#DC2626' : 'var(--wa-divider)'}`, background: 'var(--wa-panel)' }}>
      <button type="button" onClick={() => setAberto((x) => !x)} className="w-full text-left px-3 py-2 flex flex-col gap-1.5">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[12.5px]">
          {aberto ? <CaretDown size={14} /> : <CaretRight size={14} />}
          <span className="tabular-nums" style={{ color: 'var(--wa-text-2)' }}>{hora(t.inicio)}</span>
          <b style={{ color: 'var(--wa-text)' }}>{quem(t)}</b>
          {t.origem && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>{t.origem === 'organico' ? 'orgânico' : t.origem}</span>}
          <span className="ml-auto text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>
            {[`${t.passos.length} passo(s)`, segundos(t.duracao_ms), t.tokens > 0 && `${t.tokens.toLocaleString('pt-BR')} tokens`,
              t.custo_usd > 0 && `US$ ${Number(t.custo_usd).toLocaleString('pt-BR', { maximumFractionDigits: 4 })}`,
              t.erros > 0 && `${t.erros} erro(s)`].filter(Boolean).join(' · ')}
          </span>
        </div>
        <div className="flex flex-wrap items-center gap-1">
          {t.passos.map((p, i) => (
            <span key={p.id} className="inline-flex items-center gap-1">
              {i > 0 && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>›</span>}
              <Elo p={p} />
            </span>
          ))}
        </div>
      </button>
      {aberto && (
        <div className="px-4 pt-1 pb-2" style={{ borderTop: '1px solid var(--wa-divider)' }}>
          {t.passos.map((p) => <Passo key={p.id} p={p} inicio={t.inicio} />)}
        </div>
      )}
    </div>
  )
}

export default function RegistroDeFluxos() {
  const [turnos, setTurnos] = useState<TurnoDoTraco[]>([])
  const [telefone, setTelefone] = useState('')
  const [filtro, setFiltro] = useState('')
  const [soErros, setSoErros] = useState(false)
  const [carregando, setCarregando] = useState(false)
  const [fim, setFim] = useState(false)
  const [erro, setErro] = useState('')

  const ler = useCallback(async (antes?: number) => {
    setCarregando(true)
    try {
      const q = new URLSearchParams({ limite: String(PAGINA) })
      if (antes) q.set('antes', String(antes))
      if (filtro) q.set('telefone', filtro)
      const r = await fetch(`/api/agentes/tracos?${q}`)
      const j = await r.json()
      if (!r.ok) throw new Error(j.error || j.erro || 'erro')
      const novos: TurnoDoTraco[] = j.turnos || []
      setTurnos((x) => (antes ? [...x, ...novos] : novos))
      setFim(novos.length < PAGINA)
      setErro('')
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'erro')
    } finally {
      setCarregando(false)
    }
  }, [filtro])

  // a primeira página relê sozinha de 30 em 30 s (as páginas de baixo ficam como estão até atualizar)
  useEffect(() => {
    void ler()
    const t = setInterval(() => { if (!document.hidden) void ler() }, 30000)
    return () => clearInterval(t)
  }, [ler])

  const vistos = soErros ? turnos.filter((t) => t.erros > 0) : turnos

  return (
    <div className="rounded-xl p-4 flex flex-col gap-3" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
      <div className="flex flex-wrap items-center gap-2">
        <div>
          <h3 className="text-[14px] font-semibold" style={{ color: 'var(--wa-text)' }}>Registro de fluxos</h3>
          <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
            Cada turno da Nay, do mais recente: por onde a mensagem passou e as ferramentas que usou. Toque para ver os passos.
          </p>
        </div>
        <form className="ml-auto flex items-center gap-1.5" onSubmit={(e) => { e.preventDefault(); setFiltro(telefone.replace(/\D/g, '')) }}>
          <div className="flex items-center gap-1 rounded-full px-2 py-1" style={{ border: '1px solid var(--wa-divider)' }}>
            <MagnifyingGlass size={14} style={{ color: 'var(--wa-text-2)' }} />
            <input value={telefone} onChange={(e) => setTelefone(e.target.value)} placeholder="telefone do lead"
                   className="bg-transparent outline-none text-[12.5px] w-[130px]" style={{ color: 'var(--wa-text)' }} />
          </div>
          <label className="flex items-center gap-1 text-[12px] cursor-pointer" style={{ color: 'var(--wa-text)' }}>
            <input type="checkbox" checked={soErros} onChange={(e) => setSoErros(e.target.checked)} /> só com erro
          </label>
          <button type="button" onClick={() => void ler()} className="p-1.5 rounded" title="Atualizar" style={{ color: 'var(--wa-text-2)' }}>
            {carregando ? <CircleNotch size={16} className="animate-spin" /> : <ArrowsClockwise size={16} />}
          </button>
        </form>
      </div>
      {erro && <p className="text-[12.5px]" style={{ color: '#DC2626' }}>Não deu para ler o registro: {erro}</p>}
      {!erro && !carregando && vistos.length === 0 && (
        <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          {soErros ? 'Nenhum turno com erro nesta página.' : 'Nenhum turno registrado ainda (os passos aparecem com a chave dos agentes ligada).'}
        </p>
      )}
      <div className="flex flex-col gap-2">
        {vistos.map((t) => <Turno key={t.turno} t={t} />)}
      </div>
      {!fim && turnos.length > 0 && (
        <button type="button" disabled={carregando} onClick={() => void ler(turnos[turnos.length - 1].primeiro)}
                className="self-center text-[12.5px] px-3 py-1 rounded-full" style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
          {carregando ? 'Carregando…' : 'Carregar mais'}
        </button>
      )}
    </div>
  )
}
