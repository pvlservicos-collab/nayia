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
 *
 * 05/11 (Pedro: "o + e - só tá mudando o tamanho dos balões, preciso que mude o tamanho da lista de chats e do menu
 * lateral, de tudo, para se encaixar melhor no PC dele"): agora é o zoom do CRM inteiro (--zoom-app, .app-zoom no
 * globals.css: o menu, a lista, a conversa e o card). A escala só da lista (--wa-escala) fica em 1 para não dobrar.
 */
import { useEffect, useState } from 'react'
import { Minus, Plus } from '@phosphor-icons/react'

const CHAVE = 'crm-zoom-da-tela'
/* do mais apertado ao mais folgado; 1 é o desenho original do WhatsApp Web */
const DEGRAUS = [0.7, 0.75, 0.8, 0.85, 0.9, 1, 1.1, 1.2]
const PADRAO = 5

function aplicar(escala: number) {
  document.documentElement.style.setProperty('--zoom-app', String(escala))
  document.documentElement.style.setProperty('--wa-escala', '1')
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
    <div className="flex items-center" role="group" aria-label="Tamanho da tela do CRM" title={`Tamanho da tela do CRM: ${pct}%`}>
      <button type="button" onClick={() => mudar(-1)} disabled={degrau === 0}
              className="app-tap-target btn-icon w-7 h-8 disabled:opacity-40" aria-label="Diminuir a tela do CRM">
        <Minus size={18} weight="bold" />
      </button>
      <button type="button" onClick={() => mudar(1)} disabled={degrau === DEGRAUS.length - 1}
              className="app-tap-target btn-icon w-7 h-8 disabled:opacity-40" aria-label="Aumentar a tela do CRM">
        <Plus size={18} weight="bold" />
      </button>
    </div>
  )
}
