'use client'

/**
 * A ABA FECHAMENTO (Pedro, 30/09/2026): os 2 checklists preenchíveis, aluguel e
 * venda, para fazer o contrato. "Enviar ao Tel" manda o que foi preenchido ao
 * WhatsApp pessoal do Tel (por enquanto). As definições e o texto moram em
 * lib/checklistFechamento. O rascunho fica no navegador até ser enviado.
 */
import { useEffect, useState } from 'react'
import { PaperPlaneRight, Trash } from '@phosphor-icons/react'
import { CHECKLISTS, type Campo, type TipoChecklist } from '@/lib/checklistFechamento'

type Valores = Record<string, string | boolean>
const RASCUNHO = (t: TipoChecklist) => `crm.fechamento.rascunho.${t}`

function ler(t: TipoChecklist): Valores {
  try { return JSON.parse(localStorage.getItem(RASCUNHO(t)) || '{}') } catch { return {} }
}
function guardar(t: TipoChecklist, v: Valores) {
  try { localStorage.setItem(RASCUNHO(t), JSON.stringify(v)) } catch { /* sem rascunho: segue */ }
}

function CampoDoChecklist({ c, valor, mudar }: { c: Campo; valor: string | boolean | undefined; mudar: (v: string | boolean) => void }) {
  if (c.tipo === 'marca') {
    return (
      <label className="flex items-start gap-2 text-sm py-1 cursor-pointer">
        <input type="checkbox" checked={valor === true} onChange={(e) => mudar(e.target.checked)} className="mt-0.5" />
        <span>{c.rotulo}</span>
      </label>
    )
  }
  const comum = {
    value: String(valor ?? ''), onChange: (e: any) => mudar(e.target.value), 'aria-label': c.rotulo,
    className: 'w-full rounded-md border px-2 py-1.5 text-sm fechamento__campo',
  }
  return (
    <label className="block text-xs py-1">
      <span className="block mb-0.5 opacity-80">{c.rotulo}</span>
      {c.tipo === 'longo' ? <textarea rows={3} {...comum} /> : <input {...comum} />}
    </label>
  )
}

export default function FechamentoChecklists() {
  const [tipo, setTipo] = useState<TipoChecklist>('locacao')
  const [valores, setValores] = useState<Valores>({})
  const [estado, setEstado] = useState<{ ok: boolean; msg: string } | null>(null)
  const [enviando, setEnviando] = useState(false)

  useEffect(() => { setValores(ler(tipo)); setEstado(null) }, [tipo])

  const mudar = (chave: string, v: string | boolean) => {
    setValores((atual) => { const novo = { ...atual, [chave]: v }; guardar(tipo, novo); return novo })
  }

  async function enviar() {
    setEnviando(true)
    setEstado(null)
    try {
      const r = await fetch('/api/parceria/fechamento/checklist', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tipo, valores }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui mandar.')
      setEstado({ ok: true, msg: j.mensagem || 'Enviado ao Tel.' })
    } catch (e: any) {
      setEstado({ ok: false, msg: e?.message || 'Não consegui mandar.' })
    } finally {
      setEnviando(false)
    }
  }

  function limpar() {
    setValores({})
    guardar(tipo, {})
    setEstado(null)
  }

  const def = CHECKLISTS[tipo]
  return (
    <div className="flex-1 min-h-0 overflow-y-auto p-4 fechamento">
      <div className="max-w-3xl mx-auto">
        <div className="flex items-center gap-2 mb-4" role="tablist" aria-label="Qual checklist">
          {(['locacao', 'venda'] as const).map((t) => (
            <button key={t} type="button" role="tab" aria-selected={tipo === t} onClick={() => setTipo(t)}
                    className={`wa-chip ${tipo === t ? 'wa-chip--on' : ''}`}>
              {t === 'locacao' ? 'Aluguel' : 'Venda'}
            </button>
          ))}
        </div>
        <h2 className="text-lg font-semibold mb-3">{def.titulo}</h2>
        {def.secoes.map((s) => (
          <fieldset key={s.titulo} className="mb-4 rounded-lg border p-3">
            <legend className="px-1 text-sm font-semibold">{s.titulo}</legend>
            <div className="grid gap-x-4 sm:grid-cols-2">
              {s.campos.map((c) => (
                <div key={c.chave} className={c.tipo === 'longo' || c.tipo === 'marca' ? 'sm:col-span-2' : ''}>
                  <CampoDoChecklist c={c} valor={valores[c.chave]} mudar={(v) => mudar(c.chave, v)} />
                </div>
              ))}
            </div>
          </fieldset>
        ))}
        <div className="flex items-center gap-3 pb-6">
          <button type="button" onClick={enviar} disabled={enviando}
                  className="flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold wa-botao-principal">
            <PaperPlaneRight size={16} /> {enviando ? 'Enviando…' : 'Enviar ao Tel'}
          </button>
          <button type="button" onClick={limpar} className="flex items-center gap-1 text-sm opacity-80">
            <Trash size={14} /> Limpar
          </button>
          {estado && <span className={`text-sm ${estado.ok ? 'text-green-700' : 'text-red-600'}`}>{estado.msg}</span>}
        </div>
      </div>
    </div>
  )
}
