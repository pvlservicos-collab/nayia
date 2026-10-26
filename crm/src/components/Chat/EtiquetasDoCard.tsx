'use client'

/**
 * AS ETIQUETAS NO CARD DO LEAD (Parceria e Captação). Pedro, 29/09: embaixo do número; 17/10: "no card do lead eu posso
 * pôr uma tag nele para ficar mais fácil saber sobre o cliente", com cor. Pôr, tirar e criar (com a cor) num menu só;
 * a lista é a mesma da prancheta da lista de conversas (src/lib/etiquetas.ts).
 */
import { useState } from 'react'
import { Check, Plus, X } from '@phosphor-icons/react'
import { CORES_DE_ETIQUETA, criarEtiqueta, marcarEtiqueta, useEtiquetas, type Etiqueta } from '@/lib/etiquetas'

export default function EtiquetasDoCard({ lead, onTagsChange, alinhar = 'centro', compacto = false }: {
  lead: { id: string; lead_tags?: Array<{ tag_id: string; tag?: any }> | null }
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  alinhar?: 'centro' | 'esquerda'
  /** 26/10 (Pedro: as tags coloridas na lista da API Oficial, onde aparecia o "2 filtrado"): na linha da conversa,
   *  pequenas, até 3, e o "+" só com o ícone; o clique não abre a conversa */
  compacto?: boolean
}) {
  const etiquetas = useEtiquetas()
  const [aberto, setAberto] = useState(false)
  const [nova, setNova] = useState('')
  const [cor, setCor] = useState(CORES_DE_ETIQUETA[5])
  const [erro, setErro] = useState('')

  const tem = (id: string) => (lead.lead_tags || []).some((lt) => lt.tag_id === id)
  const doLead = (lead.lead_tags || [])
    .map((lt: any) => etiquetas.find((t) => t.id === lt.tag_id) || lt.tag)
    .filter((t: any) => t && !String(t.name).startsWith('Nay:'))

  const alternar = async (t: Etiqueta) => {
    const ja = tem(t.id)
    onTagsChange?.(lead.id, t.id, ja ? 'remove' : 'add', t)
    try { await marcarEtiqueta(lead.id, t.id, !ja) } catch { onTagsChange?.(lead.id, t.id, ja ? 'add' : 'remove', t) }
  }
  const criar = async () => {
    if (!nova.trim()) return
    setErro('')
    try {
      const t = await criarEtiqueta(nova, cor)
      setNova('')
      if (!tem(t.id)) void alternar(t)
    } catch (e: any) { setErro(e?.message || 'não consegui criar') }
  }

  if (compacto) {
    return (
      <span className="relative inline-flex items-center gap-1 flex-shrink-0 max-w-[60%]"
            onClick={(e) => e.stopPropagation()} onContextMenu={(e) => e.stopPropagation()}
            onPointerDown={(e) => e.stopPropagation()}>
        {doLead.slice(0, 3).map((t: any) => (
          <span key={t.id} className="inline-flex items-center rounded-full px-1.5 h-[18px] text-[11px] font-semibold leading-none truncate max-w-[110px]"
                style={{ color: '#fff', background: t.color?.startsWith('#') ? t.color : '#64748b' }} title={t.name}>
            {t.name}
          </span>
        ))}
        {doLead.length > 3 && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>+{doLead.length - 3}</span>}
        <button type="button" onClick={() => setAberto((m) => !m)} aria-expanded={aberto}
                className="inline-flex items-center justify-center w-[18px] h-[18px] rounded-full hover:bg-[var(--wa-row-hover)]"
                style={{ color: 'var(--wa-text-2)', border: '1px dashed var(--wa-divider)' }} title="Pôr, tirar ou criar etiqueta" aria-label="Etiquetas">
          <Plus size={10} weight="bold" />
        </button>
        {aberto && menu('left-0')}
      </span>
    )
  }

  return (
    <div className={`flex flex-wrap items-center gap-1.5 relative ${alinhar === 'centro' ? 'justify-center' : 'justify-start'}`}>
      {doLead.map((t: any) => (
        <span key={t.id} className="wa-marca !pr-1 inline-flex items-center gap-1"
              style={{ color: t.color?.startsWith('#') ? t.color : 'var(--wa-text-2)' }}>
          <span className="w-2 h-2 rounded-full" style={{ background: t.color }} />
          {t.name}
          <button type="button" onClick={() => void alternar(t)} className="rounded-full hover:bg-black/10 p-0.5"
                  title={`Tirar "${t.name}"`} aria-label={`Tirar ${t.name}`}>
            <X size={10} weight="bold" />
          </button>
        </span>
      ))}
      <button type="button" onClick={() => setAberto((m) => !m)} className="wa-chip !h-7 !px-2.5 !text-[12.5px]"
              aria-expanded={aberto} title="Pôr ou criar etiqueta">
        <Plus size={12} weight="bold" /> Etiqueta
      </button>
      {aberto && menu(alinhar === 'centro' ? 'left-1/2 -translate-x-1/2' : 'left-0')}
    </div>
  )

  // o menu de pôr, tirar e criar (o mesmo no card e na linha da lista)
  function menu(posicao: string) {
    return (
        <div className={`absolute top-full mt-1.5 z-30 w-[270px] max-h-[340px] overflow-y-auto wa-rolagem rounded-xl shadow-2xl p-1.5 text-left ${posicao}`}
             style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
          {!etiquetas.length && (
            <p className="px-2.5 py-2 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>Nenhuma etiqueta ainda: crie a primeira aqui embaixo.</p>
          )}
          {etiquetas.map((t) => (
            <button key={t.id} type="button" onClick={() => void alternar(t)}
                    className="w-full flex items-center gap-2 px-2.5 py-1.5 rounded-lg text-[13.5px] hover:bg-[var(--wa-row-hover)]"
                    style={{ color: 'var(--wa-text)' }}>
              <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: t.color }} />
              <span className="flex-1 truncate">{t.name}</span>
              {tem(t.id) && <Check size={14} weight="bold" style={{ color: 'var(--wa-green)' }} />}
            </button>
          ))}
          <form className="mt-1 pt-1.5" style={{ borderTop: '1px solid var(--wa-divider)' }}
                onSubmit={(e) => { e.preventDefault(); void criar() }}>
            <div className="flex items-center gap-1">
              <input value={nova} onChange={(e) => setNova(e.target.value)} placeholder="Criar etiqueta…" maxLength={40}
                     className="flex-1 min-w-0 h-8 px-2 rounded-md text-[13px]" style={{ background: 'var(--wa-app)', color: 'var(--wa-text)' }} />
              <button type="submit" disabled={!nova.trim()} className="wa-icone-btn !w-8 !h-8 disabled:opacity-40" aria-label="Criar etiqueta">
                <Plus size={15} weight="bold" />
              </button>
            </div>
            <div className="flex flex-wrap gap-1.5 px-1 pt-2" role="radiogroup" aria-label="Cor da etiqueta">
              {CORES_DE_ETIQUETA.map((c) => (
                <button key={c} type="button" role="radio" aria-checked={cor === c} onClick={() => setCor(c)}
                        className="w-5 h-5 rounded-full" title="Cor da etiqueta"
                        style={{ background: c, outline: cor === c ? '2px solid var(--wa-text)' : 'none', outlineOffset: 2 }} />
              ))}
            </div>
            {erro && <p className="px-1 pt-1 text-[11.5px]" style={{ color: 'var(--wa-tag-tel)' }}>{erro}</p>}
          </form>
          <button type="button" onClick={() => setAberto(false)} className="w-full mt-1 text-[12.5px] py-1" style={{ color: 'var(--wa-text-2)' }}>Fechar</button>
        </div>
    )
  }
}
