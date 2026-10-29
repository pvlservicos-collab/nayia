'use client'

/**
 * A LUPINHA DA ABA PROPRIETÁRIOS (Pedro, 30/09/2026): "pesquisar por nome ou se
 * for número, e se for número que não temos, ele pode abrir uma conversa com
 * esse número por lá".
 *
 * Quem usa passa o texto para o filtro da lista (`aoMudar`) e diz quantas
 * conversas sobraram (`achados`). Quando o texto é um telefone (10 a 13
 * dígitos) e não sobrou nenhuma, aparece "Abrir conversa com ...": cria (ou
 * acha) o lead e abre.
 *
 * A LUPA DE CIMA PERGUNTA POR QUAL NÚMERO (Pedro, 02/10/2026): "ela tá abrindo
 * por padrão no de captação mas não é para fazer isso, é para a abinha da lupa
 * abrir para escolher o de parceria ou de captação". Antes a conversa nascia na
 * linha da aba em que a pessoa estava. Agora são dois botões, Parceria e
 * Captação; escolher a outra linha leva para a tela dela, já na conversa.
 * Quem só responde na captação (captacaoSoResponde.ts) vê a Captação apagada.
 */
import { useState } from 'react'
import { MagnifyingGlass, ChatCircleText, X } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { CAMINHO_DA_LINHA, type LinhaWhatsapp } from '@/lib/leadChannel'
import { RECUSA_DA_CAPTACAO, soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'

export function casaNaBusca(texto: string, lead: { title?: string | null; phone?: string | null }): boolean {
  const t = texto.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  if (!t) return true
  const digitos = t.replace(/\D/g, '')
  if (digitos.length >= 4 && String(lead.phone || '').replace(/\D/g, '').includes(digitos)) return true
  const nome = String(lead.title || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  return nome.includes(t)
}

const ESCOLHAS: Array<{ linha: LinhaWhatsapp; rotulo: string }> = [
  { linha: 'parceria', rotulo: 'Parceria' },
  { linha: 'captacao', rotulo: 'Captação' },
]

export default function BuscaDaLista({ texto, aoMudar, achados, aoAbrir, placeholder, linha, soBotao }: {
  /** a linha da tela em que a busca está (parceria, captacao, oficial) */
  linha?: string
  /** só os botões "Iniciar conversa", sem o campo (a lupa de cima já tem o campo) */
  soBotao?: boolean
  texto: string
  aoMudar: (t: string) => void
  achados: number
  aoAbrir: (leadId: string) => void
  placeholder?: string
}) {
  const { profileName, user } = useAuth()
  const soResponde = soRespondeNaCaptacao(profileName || user?.name)
  const [abrindo, setAbrindo] = useState<string | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const digitos = texto.replace(/\D/g, '')
  const ehNumero = digitos.length >= 10 && digitos.length <= 13 && /^[\d\s()+-]+$/.test(texto.trim())

  async function abrir(escolhida: string) {
    setAbrindo(escolhida)
    setErro(null)
    try {
      const r = await fetch('/api/leads/abrir', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone: digitos, linha: escolhida }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui abrir a conversa.')
      aoMudar('')
      // conversa de outra linha mora em outra tela: vai para lá, já aberta
      const caminho = CAMINHO_DA_LINHA[escolhida as LinhaWhatsapp]
      if (escolhida !== (linha || 'parceria') && caminho) window.location.href = `${caminho}?leadId=${j.id}`
      else aoAbrir(j.id)
    } catch (e: any) {
      setErro(e?.message || 'Não consegui abrir a conversa.')
    } finally {
      setAbrindo(null)
    }
  }

  if (soBotao) {
    if (!ehNumero || achados > 0) return null
    // 29/10 (Pedro: "na parte de Leads, para falar com um contato novo, um botão: quando alguém pesquisa um número lá em
    // cima aparece 'Criar conversa'"): o botão grande abre a conversa NESTA linha; as outras linhas ficam como atalho.
    const aqui = (linha === 'captacao' || linha === 'parceria') ? linha : 'parceria'
    const aquiBarrada = aqui === 'captacao' && soResponde
    const outras = ESCOLHAS.filter((e) => e.linha !== aqui)
    return (
      <div className="px-4 pb-2">
        <p className="text-[12.5px] mb-1.5" style={{ color: 'var(--wa-text-2)' }}>
          Não há conversa com {texto.trim()}.
        </p>
        <button type="button" onClick={() => abrir(aqui)} disabled={!!abrindo || aquiBarrada}
                title={aquiBarrada ? RECUSA_DA_CAPTACAO : 'Criar a conversa com este número nesta tela'}
                className="flex items-center gap-2 text-sm font-medium wa-busca__abrir disabled:opacity-45 disabled:cursor-not-allowed">
          <ChatCircleText size={16} />
          {abrindo === aqui ? 'Abrindo…' : 'Criar conversa'}
        </button>
        <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs" style={{ color: 'var(--wa-text-2)' }}>
          {outras.map((e) => {
            const barrada = e.linha === 'captacao' && soResponde
            return (
              <button key={e.linha} type="button" onClick={() => abrir(e.linha)} disabled={!!abrindo || barrada}
                      title={barrada ? RECUSA_DA_CAPTACAO : `Abrir a conversa pelo WhatsApp da ${e.rotulo}`}
                      className="underline disabled:opacity-45 disabled:cursor-not-allowed">
                {abrindo === e.linha ? 'Abrindo…' : `ou criar pela ${e.rotulo}`}
              </button>
            )
          })}
        </div>
        {soResponde && (
          <p className="mt-1.5 text-xs" style={{ color: 'var(--wa-text-2)' }}>{RECUSA_DA_CAPTACAO}</p>
        )}
        {erro && <p className="mt-1 text-xs text-red-600">{erro}</p>}
      </div>
    )
  }

  return (
    <div className="px-4 pb-2">
      <label className="flex items-center gap-2 rounded-lg px-3 py-1.5 wa-busca">
        <MagnifyingGlass size={16} aria-hidden />
        <input
          value={texto}
          onChange={(e) => { aoMudar(e.target.value); setErro(null) }}
          placeholder={placeholder || 'Pesquisar por nome ou número'}
          aria-label={placeholder || 'Pesquisar por nome ou número'}
          className="flex-1 bg-transparent outline-none text-sm"
        />
        {texto && (
          <button type="button" onClick={() => aoMudar('')} aria-label="Limpar a busca"><X size={14} /></button>
        )}
      </label>
      {ehNumero && achados === 0 && (
        <button type="button" onClick={() => abrir(linha || 'parceria')} disabled={!!abrindo}
                className="mt-2 flex items-center gap-2 text-sm font-medium wa-busca__abrir">
          <ChatCircleText size={16} />
          {abrindo ? 'Abrindo…' : `Abrir conversa com ${texto.trim()}`}
        </button>
      )}
      {erro && <p className="mt-1 text-xs text-red-600">{erro}</p>}
    </div>
  )
}
