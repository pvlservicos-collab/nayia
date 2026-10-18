'use client'

/**
 * A PRANCHETA (Pedro, 17/10/2026: "nos 2 números um iconezinho de tag ... se eu clico nesse ícone eu posso filtrar pelas
 * tags se eu quiser ou criar novas no mesmo menu que fica escondido e abre quando eu clico no iconezinho, pode ser uma
 * pranchetinha"). Fica no alto da lista de conversas. O menu: as etiquetas da equipe com quantas conversas desta linha
 * têm cada uma (marcar filtra; várias = qualquer uma delas), e embaixo criar uma nova com a cor. No modo "editar", a cor
 * de cada uma muda com um clique e ela pode ser apagada.
 */
import { useEffect, useRef, useState } from 'react'
import { Check, ClipboardText, PencilSimple, Plus, Trash } from '@phosphor-icons/react'
import { apagarEtiqueta, CORES_DE_ETIQUETA, criarEtiqueta, mudarCorDaEtiqueta, useEtiquetas } from '@/lib/etiquetas'

export default function PranchetaDeEtiquetas({ escolhidas, aoAlternar, aoLimpar, contagem }: {
  escolhidas: string[]
  aoAlternar: (id: string) => void
  aoLimpar: () => void
  contagem: Record<string, number>
}) {
  const etiquetas = useEtiquetas()
  const [aberto, setAberto] = useState(false)
  const [editando, setEditando] = useState(false)
  const [nova, setNova] = useState('')
  const [cor, setCor] = useState(CORES_DE_ETIQUETA[5])
  const [erro, setErro] = useState('')
  const caixa = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!aberto) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [aberto])

  const criar = async () => {
    if (!nova.trim()) return
    setErro('')
    try { await criarEtiqueta(nova, cor); setNova('') } catch (e: any) { setErro(e?.message || 'não consegui criar') }
  }
  const proximaCor = async (id: string, atual: string) => {
    const i = CORES_DE_ETIQUETA.indexOf(atual)
    try { await mudarCorDaEtiqueta(id, CORES_DE_ETIQUETA[(i + 1) % CORES_DE_ETIQUETA.length]) } catch { /* fica a de antes */ }
  }
  const apagar = async (id: string, nome: string) => {
    if (!window.confirm(`Apagar a etiqueta "${nome}"? Ela sai de todos os leads.`)) return
    try { await apagarEtiqueta(id); if (escolhidas.includes(id)) aoAlternar(id) } catch { /* fica */ }
  }

  return (
    <div className="relative" ref={caixa}>
      <button type="button" onClick={() => setAberto((v) => !v)} aria-expanded={aberto}
              className={`wa-icone-btn relative ${escolhidas.length > 0 ? 'wa-icone-btn--on' : ''}`} title="Etiquetas: filtrar ou criar">
        <ClipboardText size={20} />
        {escolhidas.length > 0 && (
          <span className="wa-badge absolute -top-0.5 -right-0.5 !min-w-[16px] !h-4 !text-[10px] !px-1">{escolhidas.length}</span>
        )}
      </button>
      {aberto && (
        <div className="absolute z-50 right-0 top-full mt-1 w-72 max-h-[420px] overflow-y-auto rounded-xl py-1.5 shadow-xl wa-rolagem"
             style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
          <div className="flex items-center justify-between px-3 py-1.5 gap-2">
            <span className="text-[11px] font-semibold uppercase tracking-wider" style={{ color: 'var(--wa-text-2)' }}>Etiquetas</span>
            <span className="flex items-center gap-3">
              {escolhidas.length > 0 && (
                <button type="button" onClick={aoLimpar} className="text-[12px] font-semibold hover:underline" style={{ color: 'var(--wa-green)' }}>
                  Limpar filtro
                </button>
              )}
              <button type="button" onClick={() => setEditando((v) => !v)} title="Mudar cor ou apagar"
                      className="text-[12px] font-semibold inline-flex items-center gap-1" style={{ color: editando ? 'var(--wa-green)' : 'var(--wa-text-2)' }}>
                <PencilSimple size={13} /> {editando ? 'Pronto' : 'Editar'}
              </button>
            </span>
          </div>
          {!etiquetas.length && (
            <p className="px-3 py-2 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
              Nenhuma etiqueta ainda. Crie aqui embaixo e ponha no card do lead.
            </p>
          )}
          {etiquetas.map((t) => {
            const on = escolhidas.includes(t.id)
            const n = contagem[t.id] || 0
            return (
              <div key={t.id} className="flex items-center hover:bg-[var(--wa-row-hover)]">
                {editando ? (
                  <button type="button" onClick={() => void proximaCor(t.id, t.color)} title="Trocar a cor"
                          className="ml-3 w-4 h-4 rounded-full flex-shrink-0" style={{ background: t.color }} />
                ) : (
                  <span className="ml-3 w-4 h-4 rounded flex items-center justify-center flex-shrink-0 border-2"
                        style={{ borderColor: t.color, backgroundColor: on ? t.color : 'transparent' }}>
                    {on && <Check size={11} weight="bold" className="text-white" />}
                  </span>
                )}
                <button type="button" onClick={() => !editando && aoAlternar(t.id)} disabled={editando}
                        className="flex-1 min-w-0 flex items-center gap-2 px-2.5 py-2 text-left text-[14px]" style={{ color: 'var(--wa-text)' }}>
                  <span className="truncate flex-1">{t.name}</span>
                  <span className="text-[12px] tabular-nums" style={{ color: 'var(--wa-text-2)' }}>{n}</span>
                </button>
                {editando && (
                  <button type="button" onClick={() => void apagar(t.id, t.name)} title="Apagar etiqueta" className="px-3 py-2"
                          style={{ color: 'var(--wa-tag-tel)' }} aria-label={`Apagar ${t.name}`}>
                    <Trash size={14} />
                  </button>
                )}
              </div>
            )
          })}
          <form className="mx-2 mt-1 pt-2" style={{ borderTop: '1px solid var(--wa-divider)' }}
                onSubmit={(e) => { e.preventDefault(); void criar() }}>
            <div className="flex items-center gap-1">
              <input value={nova} onChange={(e) => setNova(e.target.value)} placeholder="Nova etiqueta…" maxLength={40}
                     className="flex-1 min-w-0 h-8 px-2 rounded-md text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)' }} />
              <button type="submit" disabled={!nova.trim()} className="wa-icone-btn !w-8 !h-8 disabled:opacity-40" aria-label="Criar etiqueta">
                <Plus size={15} weight="bold" />
              </button>
            </div>
            <div className="flex flex-wrap gap-1.5 px-1 py-2" role="radiogroup" aria-label="Cor da nova etiqueta">
              {CORES_DE_ETIQUETA.map((c) => (
                <button key={c} type="button" role="radio" aria-checked={cor === c} onClick={() => setCor(c)}
                        className="w-5 h-5 rounded-full" title="Cor da etiqueta"
                        style={{ background: c, outline: cor === c ? '2px solid var(--wa-text)' : 'none', outlineOffset: 2 }} />
              ))}
            </div>
            {erro && <p className="px-1 pb-1 text-[11.5px]" style={{ color: 'var(--wa-tag-tel)' }}>{erro}</p>}
          </form>
        </div>
      )}
    </div>
  )
}
