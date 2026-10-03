'use client'

/**
 * A NOTIFICAÇÃO DE QUE ALGO MUDOU (Pedro, 03/10/2026): "coloca um aviso claro quando
 * eu mudar o status de um contato lá no CRM; por exemplo, tem uns que eu coloco para
 * Todos e não salva; põe uma notificaçãozinha".
 *
 * Um cartão que sobe no pé da tela, por cima de tudo, e some sozinho: verde quando
 * foi, laranja quando salvou mas ficou em outro lugar (com o motivo), vermelho
 * quando não salvou. O laranja e o vermelho ficam mais tempo: são os que precisam
 * ser lidos. Fecha no ×.
 *
 * Vai por portal para o <body> porque o card do contato rola e é estreito: um aviso
 * dentro dele some com a rolagem. `chat-theme` traz as cores do chat para fora dele.
 */
import { useEffect } from 'react'
import { createPortal } from 'react-dom'
import { CheckCircle, Warning, X, XCircle } from '@phosphor-icons/react'

export interface AvisoNaTela {
  tom: 'ok' | 'aviso' | 'erro'
  titulo: string
  texto?: string
}

const COR = { ok: '#16a34a', aviso: '#d97706', erro: '#dc2626' } as const

export default function AvisoFlutuante({ aviso, aoFechar }: {
  aviso: AvisoNaTela | null
  /** estável (useCallback): trocar a função a cada desenho recomeçaria a contagem */
  aoFechar: () => void
}) {
  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(aoFechar, aviso.tom === 'ok' ? 6000 : 15000)
    return () => clearTimeout(t)
  }, [aviso, aoFechar])

  if (!aviso || typeof document === 'undefined') return null
  const cor = COR[aviso.tom]
  const Icone = aviso.tom === 'ok' ? CheckCircle : aviso.tom === 'aviso' ? Warning : XCircle
  return createPortal(
    <div className="chat-theme fixed z-[200] left-1/2 -translate-x-1/2 bottom-6 w-[min(92vw,480px)] pointer-events-none">
      <div role={aviso.tom === 'ok' ? 'status' : 'alert'} aria-live={aviso.tom === 'ok' ? 'polite' : 'assertive'}
           className="pointer-events-auto flex items-start gap-2.5 rounded-xl shadow-2xl px-4 py-3"
           style={{ background: 'var(--wa-panel, #fff)', color: 'var(--wa-text, #111b21)', border: `2px solid ${cor}` }}>
        <Icone size={24} weight="fill" style={{ color: cor }} className="flex-shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <p className="text-[15px] font-semibold leading-5">{aviso.titulo}</p>
          {aviso.texto && <p className="text-[13px] leading-[18px] mt-1" style={{ color: 'var(--wa-text-2, #667781)' }}>{aviso.texto}</p>}
        </div>
        <button type="button" onClick={aoFechar} aria-label="Fechar o aviso" title="Fechar" className="flex-shrink-0 mt-0.5 opacity-70 hover:opacity-100">
          <X size={16} />
        </button>
      </div>
    </div>,
    document.body,
  )
}
