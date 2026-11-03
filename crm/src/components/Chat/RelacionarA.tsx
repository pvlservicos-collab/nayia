'use client'

/**
 * "RELACIONAR A" (Pedro, 03/11/2026: "uma nova opção ao clicar em cima do contato, embaixo da adicionar tag, Relacionar a,
 * vai abrir tipo um overlay na tela e vai pedir para eu clicar em outro contato; quando eu clicar no outro contato essa
 * conversa vai ficar minimizada embaixo do outro").
 *
 * Este é só o overlay: escurece a tela MENOS a lista de conversas (quatro faixas em volta do retângulo dela, sem depender de
 * z-index dos pais) e mostra o pedido. Quem pega o clique no outro contato é a própria lista (LeadList, handleLeadClick), que
 * grava pelo mesmo caminho do "Dentro de…" (POST /api/leads/<id>/organizar { dentroDe: { pai, ligar: true } }). Esc, o
 * botão Cancelar ou um clique fora da lista desistem.
 */
import { useEffect, useLayoutEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { CircleNotch, TreeStructure, X } from '@phosphor-icons/react'

interface Props {
  /** o nome de quem vai ficar embaixo */
  nome: string
  /** a lista de conversas: fica clara e clicável */
  alvo: React.RefObject<HTMLElement | null>
  ocupado: boolean
  erro: string
  aoCancelar: () => void
}

export default function RelacionarA({ nome, alvo, ocupado, erro, aoCancelar }: Props) {
  const [r, setR] = useState<DOMRect | null>(null)
  useLayoutEffect(() => {
    const medir = () => setR(alvo.current?.getBoundingClientRect() ?? null)
    medir()
    window.addEventListener('resize', medir)
    window.addEventListener('scroll', medir, true)
    return () => { window.removeEventListener('resize', medir); window.removeEventListener('scroll', medir, true) }
  }, [alvo])
  useEffect(() => {
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') aoCancelar() }
    window.addEventListener('keydown', tecla)
    return () => window.removeEventListener('keydown', tecla)
  }, [aoCancelar])
  if (!r || typeof document === 'undefined') return null

  const escuro: React.CSSProperties = { position: 'fixed', background: 'rgba(0,0,0,.45)', zIndex: 80 }
  const faixas: React.CSSProperties[] = [
    { top: 0, left: 0, right: 0, height: Math.max(0, r.top) },
    { top: r.bottom, left: 0, right: 0, bottom: 0 },
    { top: r.top, left: 0, width: Math.max(0, r.left), height: r.height },
    { top: r.top, left: r.right, right: 0, height: r.height },
  ]
  return createPortal(
    <>
      {faixas.map((f, i) => <div key={i} style={{ ...escuro, ...f }} onClick={aoCancelar} aria-hidden />)}
      {/* a borda da lista, para o olho ir até ela */}
      <div style={{ position: 'fixed', top: r.top, left: r.left, width: r.width, height: r.height, zIndex: 80, pointerEvents: 'none',
                    boxShadow: 'inset 0 0 0 3px var(--wa-green, #00a884)', borderRadius: 4 }} aria-hidden />
      <div role="dialog" aria-label="Relacionar conversa"
           style={{ position: 'fixed', top: 12, left: '50%', transform: 'translateX(-50%)', zIndex: 81, maxWidth: 'min(560px, calc(100vw - 32px))',
                    background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}
           className="rounded-xl shadow-xl px-4 py-3 flex items-start gap-3">
        {ocupado ? <CircleNotch size={22} className="animate-spin flex-shrink-0 mt-0.5" /> : <TreeStructure size={22} className="flex-shrink-0 mt-0.5" style={{ color: 'var(--wa-green, #00a884)' }} />}
        <div className="flex-1 min-w-0">
          <p className="text-[14px] font-semibold">Relacionar {nome}</p>
          <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
            {ocupado ? 'Relacionando…' : 'Clique no outro contato na lista. Esta conversa vai ficar minimizada embaixo dele.'}
          </p>
          {erro && <p className="text-[13px] mt-1 text-red-500">{erro}</p>}
        </div>
        <button type="button" onClick={aoCancelar} className="flex items-center gap-1 text-[13px] px-2 py-1 rounded-lg hover:bg-black/5 dark:hover:bg-white/10"
                style={{ color: 'var(--wa-text-2)' }} title="Cancelar (Esc)">
          <X size={15} /> Cancelar
        </button>
      </div>
    </>,
    document.body,
  )
}
