'use client'

/**
 * CARTÃO DE CONTATO RECEBIDO (Pedro, 30/10/2026: "o nosso CRM hoje não recebe contato WPP LEADS; precisamos colocar
 * para aparecer o contato na hora que é enviado o card do contato, um cardzinho com a opção Criar contato; quando
 * clica se cria um contato com esse contato que foi enviado para nós").
 *
 * O nome e os números vêm de `metadata.contato_compartilhado` (zapiInbound.ts). "Criar contato" abre a conversa com
 * esse número no WhatsApp Leads -- a mesma rota do botão Contato novo (/api/leads/abrir: acha a conversa, se já
 * existe, ou cria) -- e leva até ela.
 */
import { useState } from 'react'
import { UserCircle, UserPlus } from '@phosphor-icons/react'
import { CAMINHO_DA_LINHA } from '@/lib/leadChannel'

function formatar(t: string) {
  const d = t.replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return t
}

export default function ContatoCompartilhado({ contato }: { contato: { nome?: string; telefones?: string[] } }) {
  const telefones = Array.isArray(contato?.telefones) ? contato.telefones : []
  const nome = String(contato?.nome || 'Contato')
  const [abrindo, setAbrindo] = useState<string | null>(null)
  const [erro, setErro] = useState<string | null>(null)

  async function criar(telefone: string) {
    setAbrindo(telefone)
    setErro(null)
    try {
      const r = await fetch('/api/leads/abrir', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone, nome: nome === 'contato' ? '' : nome, linha: 'captacao' }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui criar o contato.')
      window.location.href = `${CAMINHO_DA_LINHA.captacao}?leadId=${j.id}`
    } catch (e: any) {
      setErro(e?.message || 'Não consegui criar o contato.')
      setAbrindo(null)
    }
  }

  return (
    <div className="mb-4 min-w-[220px] rounded-lg bg-black/10 p-2">
      <div className="flex items-center gap-2">
        <UserCircle size={34} weight="fill" className="flex-shrink-0 opacity-70" />
        <div className="min-w-0">
          <p className="text-[14px] font-semibold truncate">{nome}</p>
          {telefones.map((t) => <p key={t} className="text-[12px] opacity-80">{formatar(t)}</p>)}
          {!telefones.length && <p className="text-[12px] opacity-70">o WhatsApp não mandou o número</p>}
        </div>
      </div>
      {telefones.map((t) => (
        <button key={t} type="button" onClick={() => void criar(t)} disabled={!!abrindo}
                className="mt-2 w-full h-8 rounded-md text-[13px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-50"
                style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
          <UserPlus size={15} weight="bold" />
          {abrindo === t ? 'Criando…' : telefones.length > 1 ? `Criar contato ${formatar(t)}` : 'Criar contato'}
        </button>
      ))}
      {erro && <p className="mt-1 text-[12px] text-red-400">{erro}</p>}
    </div>
  )
}
