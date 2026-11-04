'use client'

/**
 * O TAMANHO DAS CONVERSAS (Pedro, 09/10/2026): "troca lá o sininho no CRM por 2
 * botões + e - que aumentam ou diminuem o tamanho das conversas para a Rayssa
 * organizar de um jeito bom".
 *
 * Os dois botões ficam onde era o sino, no alto. Eles mexem numa única
 * variável de CSS (--wa-escala) no <html>, e a linha da lista de conversas
 * (foto, nome, prévia, hora, marcas -- ver .wa-linha no globals.css) é toda
 * escrita em função dela. A escolha é de quem está usando o navegador: fica
 * no localStorage, não no banco, para a Rayssa e o Tel terem cada um o seu.
 */
import { useEffect, useState } from 'react'
import { Minus, Plus } from '@phosphor-icons/react'

const CHAVE = 'crm-tamanho-conversas'
/* do mais apertado ao mais folgado; 1 é o desenho original do WhatsApp Web */
const DEGRAUS = [0.8, 0.9, 1, 1.15, 1.3, 1.5]
const PADRAO = 2

function aplicar(escala: number) {
  document.documentElement.style.setProperty('--wa-escala', String(escala))
}

export default function TamanhoDasConversas() {
  const [degrau, setDegrau] = useState(PADRAO)

  useEffect(() => {
    let d = PADRAO
    try {
      const guardado = Number(localStorage.getItem(CHAVE))
      if (DEGRAUS.includes(guardado)) d = DEGRAUS.indexOf(guardado)
    } catch { /* navegador sem localStorage: fica no padrão */ }
    setDegrau(d)
    aplicar(DEGRAUS[d])
  }, [])

  function mudar(passo: 1 | -1) {
    const d = Math.min(DEGRAUS.length - 1, Math.max(0, degrau + passo))
    setDegrau(d)
    aplicar(DEGRAUS[d])
    try { localStorage.setItem(CHAVE, String(DEGRAUS[d])) } catch { /* sem localStorage a escolha vale só até recarregar */ }
  }

  const pct = Math.round(DEGRAUS[degrau] * 100)
  return (
    <div className="flex items-center" role="group" aria-label="Tamanho das conversas" title={`Tamanho das conversas: ${pct}%`}>
      <button type="button" onClick={() => mudar(-1)} disabled={degrau === 0}
              className="app-tap-target btn-icon w-7 h-8 disabled:opacity-40" aria-label="Diminuir o tamanho das conversas">
        <Minus size={18} weight="bold" />
      </button>
      <button type="button" onClick={() => mudar(1)} disabled={degrau === DEGRAUS.length - 1}
              className="app-tap-target btn-icon w-7 h-8 disabled:opacity-40" aria-label="Aumentar o tamanho das conversas">
        <Plus size={18} weight="bold" />
      </button>
    </div>
  )
}
