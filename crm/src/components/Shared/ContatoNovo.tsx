'use client'

/**
 * CONTATO NOVO (Pedro, 29/10/2026): "lá em cima coloca um botão também Contato novo que faz isso" -- o mesmo
 * "Criar conversa" da lupa do WhatsApp Leads (BuscaDaLista), no alto do CRM, ao lado de Respostas Tel.
 * Digita o número, escolhe o WhatsApp (o da tela em que está; fora das conversas, o Leads) e abre a conversa
 * já pronta para escrever. Quem só responde na captação vê o Leads apagado.
 */
import { useEffect, useRef, useState } from 'react'
import { usePathname } from 'next/navigation'
import { UserPlus, ChatCircleText } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { CAMINHO_DA_LINHA, type LinhaWhatsapp } from '@/lib/leadChannel'
import { RECUSA_DA_CAPTACAO, soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'

const ESCOLHAS: Array<{ linha: LinhaWhatsapp; rotulo: string }> = [
  { linha: 'captacao', rotulo: 'WhatsApp Leads' },
  { linha: 'parceria', rotulo: 'WhatsApp Parceria' },
]

export default function ContatoNovo() {
  const pathname = usePathname()
  const { profileName, user } = useAuth()
  const soResponde = soRespondeNaCaptacao(profileName || user?.name)
  const [aberto, setAberto] = useState(false)
  const [numero, setNumero] = useState('')
  const [abrindo, setAbrindo] = useState<string | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const caixa = useRef<HTMLDivElement>(null)

  const digitos = numero.replace(/\D/g, '')
  const ehNumero = digitos.length >= 10 && digitos.length <= 13
  const daTela: LinhaWhatsapp = pathname.startsWith('/chat/parceria') ? 'parceria' : 'captacao'
  const aqui: LinhaWhatsapp = daTela === 'captacao' && soResponde ? 'parceria' : daTela

  useEffect(() => { setAberto(false) }, [pathname])
  useEffect(() => {
    if (!aberto) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [aberto])

  async function abrir(linha: LinhaWhatsapp) {
    if (!ehNumero) { setErro('Digite o número com DDD.'); return }
    setAbrindo(linha)
    setErro(null)
    try {
      const r = await fetch('/api/leads/abrir', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone: digitos, linha }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui abrir a conversa.')
      window.location.href = `${CAMINHO_DA_LINHA[linha]}?leadId=${j.id}`
    } catch (e: any) {
      setErro(e?.message || 'Não consegui abrir a conversa.')
      setAbrindo(null)
    }
  }

  return (
    <div className="relative" ref={caixa}>
      <button
        type="button"
        onClick={() => { setAberto((v) => !v); setErro(null) }}
        aria-expanded={aberto}
        title="Contato novo: criar conversa com um número"
        className={`app-tap-target flex items-center justify-center gap-1.5 h-9 px-2.5 lg:px-3 rounded-lg text-[13px] sm:text-sm font-semibold whitespace-nowrap border transition-colors ${aberto
          ? 'bg-graphite-6 border-white/15 text-accent-2'
          : 'border-line text-ink hover:border-accent/60'
          }`}
      >
        <UserPlus size={16} weight={aberto ? 'fill' : 'regular'} />
        <span className="hidden min-[2000px]:inline">Contato novo</span>
      </button>

      {aberto && (
        <div className="absolute right-0 top-full mt-2 w-72 glass-raised rounded-xl p-3 z-50 animate-in fade-in slide-in-from-top-2">
          <p className="text-sm font-semibold text-ink mb-2">Contato novo</p>
          <input
            autoFocus
            inputMode="tel"
            value={numero}
            onChange={(e) => { setNumero(e.target.value); setErro(null) }}
            onKeyDown={(e) => { if (e.key === 'Enter') abrir(aqui); if (e.key === 'Escape') setAberto(false) }}
            placeholder="Número com DDD"
            aria-label="Número do contato novo"
            className="w-full h-9 px-3 rounded-lg border border-line bg-transparent text-sm text-ink outline-none focus:border-accent/60"
          />
          <button type="button" onClick={() => abrir(aqui)} disabled={!!abrindo || !ehNumero}
                  className="mt-2 w-full flex items-center justify-center gap-2 h-9 rounded-lg bg-accent text-white text-sm font-semibold disabled:opacity-45 disabled:cursor-not-allowed">
            <ChatCircleText size={16} />
            {abrindo === aqui ? 'Abrindo…' : `Criar conversa no ${ESCOLHAS.find((e) => e.linha === aqui)?.rotulo}`}
          </button>
          <div className="mt-1.5 text-xs text-muted">
            {ESCOLHAS.filter((e) => e.linha !== aqui).map((e) => {
              const barrada = e.linha === 'captacao' && soResponde
              return (
                <button key={e.linha} type="button" onClick={() => abrir(e.linha)} disabled={!!abrindo || barrada || !ehNumero}
                        title={barrada ? RECUSA_DA_CAPTACAO : `Criar a conversa pelo ${e.rotulo}`}
                        className="underline disabled:opacity-45 disabled:cursor-not-allowed">
                  {abrindo === e.linha ? 'Abrindo…' : `ou criar pelo ${e.rotulo}`}
                </button>
              )
            })}
          </div>
          {soResponde && <p className="mt-1.5 text-xs text-muted">{RECUSA_DA_CAPTACAO}</p>}
          {erro && <p className="mt-1.5 text-xs text-red-600">{erro}</p>}
        </div>
      )}
    </div>
  )
}
