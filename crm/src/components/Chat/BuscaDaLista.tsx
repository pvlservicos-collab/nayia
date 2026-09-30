'use client'

/**
 * A LUPINHA DA ABA PROPRIETÁRIOS (Pedro, 30/09/2026): "pesquisar por nome ou se
 * for número, e se for número que não temos, ele pode abrir uma conversa com
 * esse número por lá".
 *
 * Quem usa passa o texto para o filtro da lista (`aoMudar`) e diz quantas
 * conversas sobraram (`achados`). Quando o texto é um telefone (10 a 13
 * dígitos) e não sobrou nenhuma, aparece "Abrir conversa com ...": cria (ou
 * acha) o lead na linha da Parceria e abre.
 */
import { useState } from 'react'
import { MagnifyingGlass, ChatCircleText, X } from '@phosphor-icons/react'

export function casaNaBusca(texto: string, lead: { title?: string | null; phone?: string | null }): boolean {
  const t = texto.trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  if (!t) return true
  const digitos = t.replace(/\D/g, '')
  if (digitos.length >= 4 && String(lead.phone || '').replace(/\D/g, '').includes(digitos)) return true
  const nome = String(lead.title || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
  return nome.includes(t)
}

export default function BuscaDaLista({ texto, aoMudar, achados, aoAbrir, placeholder }: {
  texto: string
  aoMudar: (t: string) => void
  achados: number
  aoAbrir: (leadId: string) => void
  placeholder?: string
}) {
  const [abrindo, setAbrindo] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const digitos = texto.replace(/\D/g, '')
  const ehNumero = digitos.length >= 10 && digitos.length <= 13 && /^[\d\s()+-]+$/.test(texto.trim())

  async function abrir() {
    setAbrindo(true)
    setErro(null)
    try {
      const r = await fetch('/api/leads/abrir', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ telefone: digitos }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui abrir a conversa.')
      aoMudar('')
      aoAbrir(j.id)
    } catch (e: any) {
      setErro(e?.message || 'Não consegui abrir a conversa.')
    } finally {
      setAbrindo(false)
    }
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
        <button type="button" onClick={abrir} disabled={abrindo}
                className="mt-2 flex items-center gap-2 text-sm font-medium wa-busca__abrir">
          <ChatCircleText size={16} />
          {abrindo ? 'Abrindo…' : `Abrir conversa com ${texto.trim()}`}
        </button>
      )}
      {erro && <p className="mt-1 text-xs text-red-600">{erro}</p>}
    </div>
  )
}
