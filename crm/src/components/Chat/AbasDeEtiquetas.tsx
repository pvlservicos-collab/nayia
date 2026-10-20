'use client'

/**
 * AS ABAS DE CADA NÚMERO SÃO ETIQUETAS (Tel, por Pedro, 20/10/2026: "troque as etapas que têm Todos, Visitas, pelas
 * tags que têm pessoas ... de forma editável, todas as etapas de todos os números editáveis").
 *
 * useAbasDaLinha(linha): as etiquetas que viram aba nesta linha (integrations.config.abas_etiquetas, /api/linhas/abas).
 * Nunca editado = as etiquetas que têm pessoas nesta linha, da mais cheia para a mais vazia.
 * <EditarAbas>: o lápis no fim da fileira. Marca quais etiquetas são aba, a ordem (setas), o nome (renomear muda a
 * etiqueta e a etapa do funil de mesmo nome, 0133) e cria etiqueta nova.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowDown, ArrowUp, Check, PencilSimple, Plus } from '@phosphor-icons/react'
import { CORES_DE_ETIQUETA, criarEtiqueta, renomearEtiqueta, useEtiquetas, type Etiqueta } from '@/lib/etiquetas'

const guardadas: Record<string, string[] | null | undefined> = {}
const ouvintes: Record<string, Set<(ids: string[] | null) => void>> = {}

export function useAbasDaLinha(linha?: string | null) {
  const [ids, setIds] = useState<string[] | null | undefined>(linha ? guardadas[linha] : null)
  useEffect(() => {
    if (!linha) return
    const o = (ouvintes[linha] ||= new Set())
    o.add(setIds)
    if (guardadas[linha] === undefined) {
      fetch(`/api/linhas/abas?linha=${linha}`).then((r) => r.json()).then((j) => {
        guardadas[linha] = Array.isArray(j?.ids) ? j.ids : null
        o.forEach((f) => f(guardadas[linha] ?? null))
      }).catch(() => { guardadas[linha] = null; o.forEach((f) => f(null)) })
    } else setIds(guardadas[linha])
    return () => { o.delete(setIds) }
  }, [linha])
  const salvar = useCallback(async (novos: string[]) => {
    if (!linha) return
    const r = await fetch('/api/linhas/abas', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ linha, ids: novos }) })
    const j = await r.json().catch(() => ({}))
    if (!r.ok) throw new Error(j?.error || 'não salvou as abas')
    guardadas[linha] = j.ids || novos
    ouvintes[linha]?.forEach((f) => f(guardadas[linha] ?? null))
  }, [linha])
  return { ids, carregou: ids !== undefined, salvar }
}

/** As abas que valem: as escolhidas, ou (nunca editado) as etiquetas com gente nesta linha. */
export function abasQueValem(ids: string[] | null | undefined, etiquetas: Etiqueta[], contagem: Record<string, number>): Etiqueta[] {
  if (Array.isArray(ids)) return ids.map((id) => etiquetas.find((t) => t.id === id)).filter(Boolean) as Etiqueta[]
  return etiquetas.filter((t) => (contagem[`tag:${t.id}`] || 0) > 0)
    .sort((a, b) => (contagem[`tag:${b.id}`] || 0) - (contagem[`tag:${a.id}`] || 0))
}

export function EditarAbas({ linha, atuais, contagem }: { linha: string; atuais: Etiqueta[]; contagem: Record<string, number> }) {
  const etiquetas = useEtiquetas()
  const { salvar } = useAbasDaLinha(linha)
  const [aberto, setAberto] = useState(false)
  const [escolha, setEscolha] = useState<string[]>([])
  const [nomes, setNomes] = useState<Record<string, string>>({})
  const [nova, setNova] = useState('')
  const [erro, setErro] = useState('')
  const [salvando, setSalvando] = useState(false)
  const caixa = useRef<HTMLDivElement>(null)

  useEffect(() => { if (aberto) { setEscolha(atuais.map((t) => t.id)); setNomes({}); setErro('') } }, [aberto]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!aberto) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [aberto])

  const alternar = (id: string) => setEscolha((l) => (l.includes(id) ? l.filter((x) => x !== id) : [...l, id]))
  const mover = (id: string, d: -1 | 1) => setEscolha((l) => {
    const i = l.indexOf(id), j = i + d
    if (i < 0 || j < 0 || j >= l.length) return l
    const c = [...l]; [c[i], c[j]] = [c[j], c[i]]; return c
  })
  const gravar = async () => {
    setSalvando(true); setErro('')
    try {
      for (const [id, nome] of Object.entries(nomes)) {
        const t = etiquetas.find((x) => x.id === id)
        if (t && nome.trim() && nome.trim() !== t.name) await renomearEtiqueta(id, nome)
      }
      await salvar(escolha)
      setAberto(false)
    } catch (e: any) { setErro(e?.message || 'não salvou') } finally { setSalvando(false) }
  }
  const criar = async () => {
    if (!nova.trim()) return
    try {
      const t = await criarEtiqueta(nova, CORES_DE_ETIQUETA[escolha.length % CORES_DE_ETIQUETA.length])
      setEscolha((l) => (l.includes(t.id) ? l : [...l, t.id]))
      setNova('')
    } catch (e: any) { setErro(e?.message || 'não criou') }
  }

  // as escolhidas primeiro (na ordem das abas), depois as outras pela contagem nesta linha
  const outras = etiquetas.filter((t) => !escolha.includes(t.id))
    .sort((a, b) => (contagem[`tag:${b.id}`] || 0) - (contagem[`tag:${a.id}`] || 0) || a.name.localeCompare(b.name, 'pt-BR'))
  const ordem = [...escolha.map((id) => etiquetas.find((t) => t.id === id)).filter(Boolean) as Etiqueta[], ...outras]

  return (
    <div className="relative flex-shrink-0" ref={caixa}>
      <button type="button" onClick={() => setAberto((v) => !v)} className="wa-icone-btn !w-8 !h-8" title="Editar as abas deste número"
              aria-expanded={aberto} aria-label="Editar as abas">
        <PencilSimple size={16} />
      </button>
      {aberto && (
        <div className="absolute right-0 top-9 z-40 w-[330px] max-h-[70vh] overflow-y-auto wa-rolagem rounded-xl shadow-2xl py-2"
             style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
          <p className="px-3 pb-1.5 text-[12px] leading-4" style={{ color: 'var(--wa-text-2)' }}>
            As abas deste número são etiquetas. Marque as que aparecem, ponha na ordem e mude o nome se quiser
            (o nome muda também na etapa do funil). O número é de conversas desta linha.
          </p>
          {ordem.map((t) => {
            const on = escolha.includes(t.id)
            return (
              <div key={t.id} className="flex items-center gap-1 px-2 py-1 hover:bg-[var(--wa-row-hover)]">
                <button type="button" onClick={() => alternar(t.id)} aria-pressed={on} aria-label={on ? `Tirar ${t.name} das abas` : `Pôr ${t.name} nas abas`}
                        className="w-5 h-5 rounded flex items-center justify-center flex-shrink-0 border-2"
                        style={{ borderColor: t.color, backgroundColor: on ? t.color : 'transparent' }}>
                  {on && <Check size={12} weight="bold" className="text-white" />}
                </button>
                <input value={nomes[t.id] ?? t.name} maxLength={40} onChange={(e) => { const v = e.target.value; setNomes((m) => ({ ...m, [t.id]: v })) }}
                       className="flex-1 min-w-0 h-7 px-2 rounded-md text-[13.5px]" aria-label={`Nome de ${t.name}`}
                       style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
                <span className="w-8 text-right text-[12px] tabular-nums" style={{ color: 'var(--wa-text-2)' }}>{contagem[`tag:${t.id}`] || 0}</span>
                {on && (
                  <>
                    <button type="button" onClick={() => mover(t.id, -1)} className="wa-icone-btn !w-6 !h-6" aria-label="Subir"><ArrowUp size={13} /></button>
                    <button type="button" onClick={() => mover(t.id, 1)} className="wa-icone-btn !w-6 !h-6" aria-label="Descer"><ArrowDown size={13} /></button>
                  </>
                )}
              </div>
            )
          })}
          <form className="flex items-center gap-1 mx-2 mt-1.5 pt-2" style={{ borderTop: '1px solid var(--wa-divider)' }}
                onSubmit={(e) => { e.preventDefault(); void criar() }}>
            <input value={nova} onChange={(e) => setNova(e.target.value)} placeholder="Nova etiqueta…" maxLength={40}
                   className="flex-1 min-w-0 h-8 px-2 rounded-md text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)' }} />
            <button type="submit" disabled={!nova.trim()} className="wa-icone-btn !w-8 !h-8 disabled:opacity-40" aria-label="Criar etiqueta"><Plus size={15} weight="bold" /></button>
          </form>
          {erro && <p className="px-3 pt-1 text-[12px]" style={{ color: 'var(--wa-tag-tel)' }}>{erro}</p>}
          <div className="flex justify-end gap-2 px-3 pt-2">
            <button type="button" className="text-[13px] px-3 h-8 rounded-full" style={{ color: 'var(--wa-text-2)' }} onClick={() => setAberto(false)}>Cancelar</button>
            <button type="button" disabled={salvando} onClick={() => void gravar()} className="text-[13px] font-semibold px-4 h-8 rounded-full disabled:opacity-50"
                    style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>{salvando ? 'Salvando…' : 'Salvar abas'}</button>
          </div>
        </div>
      )}
    </div>
  )
}
