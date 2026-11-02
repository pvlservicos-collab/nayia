'use client'

/**
 * PEDIR NOS GRUPOS (Pedro, 01/11/2026): "um campo Pedir nos grupos de WhatsApp, um campo de mensagem, o cara digita e
 * quando clica enviar, é enviado do número Parceria nos grupos onde a Nay pede busca de imóveis".
 * Fica dentro da Busca do lead (BuscasDoLead). Os grupos são os da busca da Nay (privado.busca_grupo); o envio é pelo
 * número da Parceria, um grupo de cada vez (/api/leads/{id}/pedir-nos-grupos), e o pedido entra na busca do lead.
 */
import { useEffect, useState } from 'react'
import { CircleNotch, PaperPlaneTilt, UsersThree } from '@phosphor-icons/react'

const COR = '#0891b2'

export default function PedirNosGrupos({ leadId, aoEnviar }: { leadId: string; aoEnviar: () => void }) {
  const [aberto, setAberto] = useState(false)
  const [texto, setTexto] = useState('')
  const [grupos, setGrupos] = useState<string[] | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)

  useEffect(() => {
    if (!aberto || grupos) return
    fetch(`/api/leads/${leadId}/pedir-nos-grupos`).then((r) => r.ok ? r.json() : null)
      .then((j) => setGrupos((j?.grupos || []).map((g: { nome: string }) => g.nome))).catch(() => setGrupos([]))
  }, [aberto, grupos, leadId])

  const enviar = async () => {
    if (texto.trim().length < 5 || enviando) return
    setEnviando(true)
    setAviso(null)
    try {
      const r = await fetch(`/api/leads/${leadId}/pedir-nos-grupos`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ texto }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok && !(j.enviados || []).length) {
        setAviso({ ok: false, texto: j.error || j.message || 'Não consegui enviar.' })
        return
      }
      const falhou = (j.falhas || []).map((f: { nome: string }) => f.nome)
      setAviso({ ok: !falhou.length, texto: `Enviado em ${j.enviados.length} grupo${j.enviados.length > 1 ? 's' : ''} pela Parceria`
        + (falhou.length ? `; não foi em: ${falhou.join(', ')}` : '') + '.' })
      setTexto('')
      aoEnviar()
    } finally {
      setEnviando(false)
    }
  }

  if (!aberto) {
    return (
      <button type="button" onClick={() => setAberto(true)}
              className="mt-2 inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-[12.5px] font-semibold"
              style={{ border: `1px solid ${COR}`, color: COR, background: 'var(--wa-panel)' }}>
        <UsersThree size={15} weight="bold" /> Pedir nos grupos de WhatsApp
      </button>
    )
  }
  return (
    <div className="mt-2 rounded-lg p-2.5" style={{ border: `1px solid ${COR}`, background: 'var(--wa-panel)' }}>
      <p className="text-[12.5px] font-semibold flex items-center gap-1.5" style={{ color: 'var(--wa-text)' }}>
        <UsersThree size={15} weight="bold" style={{ color: COR }} /> Pedir nos grupos de WhatsApp
      </p>
      <p className="text-[11.5px] mt-0.5" style={{ color: 'var(--wa-text-2)' }}
         title={(grupos || []).join('\n')}>
        Sai pelo número da Parceria {grupos ? `em ${grupos.length} grupo${grupos.length === 1 ? '' : 's'} de busca` : '…'}
      </p>
      <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={4} maxLength={2000}
                placeholder="✅ PRECISO DE APARTAMENTO P/ LOCAÇÃO&#10;📍 Parque 10 ou Flores&#10;🛏️ 2 quartos&#10;💰 até R$ 3.000"
                className="mt-2 w-full rounded-md px-2.5 py-2 text-[13px] leading-5 outline-none resize-y"
                style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-input)', color: 'var(--wa-text)' }} />
      <div className="mt-1.5 flex items-center justify-between gap-2">
        <button type="button" onClick={() => { setAberto(false); setAviso(null) }}
                className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Fechar</button>
        <button type="button" onClick={() => void enviar()} disabled={enviando || texto.trim().length < 5}
                className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-[12.5px] font-semibold text-white disabled:opacity-50"
                style={{ background: COR }}>
          {enviando ? <CircleNotch size={14} className="animate-spin" /> : <PaperPlaneTilt size={14} weight="bold" />}
          {enviando ? 'Enviando…' : 'Enviar'}
        </button>
      </div>
      {aviso && (
        <p className="text-[12px] mt-1.5" style={{ color: aviso.ok ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>{aviso.texto}</p>
      )}
    </div>
  )
}
