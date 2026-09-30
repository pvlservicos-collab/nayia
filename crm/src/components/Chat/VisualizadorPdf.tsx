'use client'

/**
 * O PDF ABRE NO CHAT (Pedro, 30/09/2026: "quero um visualizador de PDF: quando
 * chegar, eu clico e abro o PDF no chat mesmo, sem precisar baixar").
 *
 * O balão do documento continua igual; no PDF, o clique abre a janela por cima
 * da conversa com o leitor de PDF do próprio navegador (a rota /api/midia serve
 * o arquivo "inline", sem forçar download). Esc ou o × fecham; "Baixar" e "Abrir
 * em outra aba" ficam no alto. Outro tipo de documento (Word, planilha) segue
 * baixando como antes -- o navegador não mostra esses.
 *
 * Celular e PDF que ainda não veio para o nosso armazém (endereço temporário da
 * Z-API) abrem em outra aba: o leitor de PDF dentro da página não existe no
 * Chrome do Android, e endereço de fora pode recusar abrir dentro de outra página.
 */
import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { ArrowSquareOut, DownloadSimple, FileText, X } from '@phosphor-icons/react'

export function ehPdf(nome: string | null | undefined, mime: string | null | undefined): boolean {
  return /application\/pdf/i.test(String(mime || '')) || /\.pdf$/i.test(String(nome || '').trim())
}

function abreDentro(url: string): boolean {
  if (typeof navigator !== 'undefined' && /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) return false
  return url.startsWith('/api/midia/') || (typeof window !== 'undefined' && url.startsWith(window.location.origin + '/api/midia/'))
}

export default function DocumentoPdf({ url, nome, ext }: { url: string; nome: string; ext: string }) {
  const [aberto, setAberto] = useState(false)

  useEffect(() => {
    if (!aberto) return
    const aoTeclar = (e: KeyboardEvent) => { if (e.key === 'Escape') setAberto(false) }
    window.addEventListener('keydown', aoTeclar)
    return () => window.removeEventListener('keydown', aoTeclar)
  }, [aberto])

  function abrir(e: React.MouseEvent) {
    e.preventDefault()
    e.stopPropagation()
    if (abreDentro(url)) setAberto(true)
    else window.open(url, '_blank', 'noopener,noreferrer')
  }

  return (
    <>
      <button type="button" onClick={abrir}
              className="flex items-center gap-3 p-2.5 rounded-[6px] w-[300px] max-w-full mb-0.5 text-left"
              style={{ background: 'var(--wa-quote)' }} title="Abrir o PDF aqui">
        <FileText size={30} weight="fill" style={{ color: '#e5252a' }} className="flex-shrink-0" />
        <span className="flex-1 min-w-0">
          <span className="block text-[14px] truncate">{nome}</span>
          <span className="block wa-hora">{ext} · clique para abrir</span>
        </span>
      </button>

      {aberto && typeof document !== 'undefined' && createPortal(
        <div className="fixed inset-0 z-[90] flex flex-col" style={{ background: 'rgba(11, 20, 26, 0.92)' }}
             role="dialog" aria-modal="true" aria-label={`PDF: ${nome}`}
             onClick={() => setAberto(false)}>
          <div className="flex items-center gap-3 px-4 h-14 flex-shrink-0" style={{ color: '#e9edef' }}
               onClick={(e) => e.stopPropagation()}>
            <FileText size={24} weight="fill" style={{ color: '#e5252a' }} className="flex-shrink-0" />
            <span className="flex-1 min-w-0 truncate text-[15px]">{nome}</span>
            <a href={url} target="_blank" rel="noopener noreferrer" title="Abrir em outra aba"
               className="p-2 rounded-full hover:bg-white/10"><ArrowSquareOut size={22} /></a>
            <a href={url} download={nome} title="Baixar"
               className="p-2 rounded-full hover:bg-white/10"><DownloadSimple size={22} /></a>
            <button type="button" onClick={() => setAberto(false)} title="Fechar (Esc)"
                    className="p-2 rounded-full hover:bg-white/10"><X size={22} /></button>
          </div>
          <div className="flex-1 min-h-0 px-4 pb-4" onClick={(e) => e.stopPropagation()}>
            <iframe src={url} title={nome} className="w-full h-full rounded-md bg-white" />
          </div>
        </div>,
        document.body,
      )}
    </>
  )
}
