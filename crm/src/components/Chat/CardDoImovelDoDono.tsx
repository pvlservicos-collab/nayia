'use client'

/**
 * O CARD DO IMÓVEL DO PROPRIETÁRIO no painel da direita do WhatsApp Leads.
 *
 * Pedro, 20/10/2026: "lá no WhatsApp de lead, quando ela for falar com um proprietário coloca um card com o imóvel do
 * proprietário no menu à direita que abre quando clico em uma conversa".
 *
 * É o mesmo card que sai no WhatsApp e nos grupos (`/api/imoveis-nay/card/<código>`, o `nai_card_do_imovel`), com a
 * foto de capa e o link da página do imóvel.
 */
import { useEffect, useState } from 'react'
import { CircleNotch, House } from '@phosphor-icons/react'
import TagParceiro from '@/components/TagParceiro'

interface Card {
  codigo: number
  card: string
  fotos: string[]
  e_parceiro: boolean
  imovel: { status: string | null; capa: string | null; total_fotos: number }
}

export default function CardDoImovelDoDono({ codigo, daCampanha }: { codigo: number; daCampanha?: boolean }) {
  const [c, setC] = useState<Card | null>(null)
  const [estado, setEstado] = useState<'lendo' | 'ok' | 'erro'>('lendo')

  useEffect(() => {
    let vivo = true
    setEstado('lendo')
    fetch(`/api/imoveis-nay/card/${codigo}`)
      .then(async (r) => (r.ok ? ((await r.json()) as Card) : null))
      .then((d) => { if (vivo) { setC(d); setEstado(d ? 'ok' : 'erro') } })
      .catch(() => { if (vivo) setEstado('erro') })
    return () => { vivo = false }
  }, [codigo])

  if (estado === 'lendo') {
    return (
      <div className="flex items-center gap-2 text-[12.5px] py-2" style={{ color: 'var(--wa-text-2)' }}>
        <CircleNotch size={14} className="animate-spin" /> Lendo o imóvel #{codigo}…
      </div>
    )
  }
  if (!c) {
    return <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>Não consegui ler o card do #{codigo}.</p>
  }

  return (
    <div className="rounded-xl overflow-hidden" style={{ background: 'var(--wa-app)', border: '1px solid var(--wa-divider)' }}>
      {c.imovel.capa
        ? <img src={c.imovel.capa} alt="" className="w-full aspect-[4/3] object-cover" loading="lazy" />
        : (
          <div className="w-full h-20 flex items-center justify-center" style={{ background: 'var(--wa-row-selected)' }}>
            <House size={28} style={{ color: 'var(--wa-text-2)' }} />
          </div>
        )}
      <div className="p-3">
        <p className="text-[11px] uppercase tracking-wide mb-1.5" style={{ color: 'var(--wa-text-2)' }}>
          Cód. {c.codigo}{c.imovel.status ? ` · ${c.imovel.status}` : ''}{daCampanha ? ' · da campanha' : ''}
          {c.imovel.total_fotos ? ` · ${c.imovel.total_fotos} foto${c.imovel.total_fotos === 1 ? '' : 's'}` : ''}
          {c.e_parceiro ? <> <TagParceiro /></> : null}
        </p>
        <pre className="text-[12.5px] leading-[1.45] whitespace-pre-wrap break-words font-sans" style={{ color: 'var(--wa-text)' }}>
{c.card}
        </pre>
        <a href={`https://imobeasy.online/imovel/${c.codigo}`} target="_blank" rel="noreferrer"
           className="mt-2.5 block text-center text-[12.5px] font-semibold py-1.5 rounded-lg"
           style={{ color: 'var(--wa-green)', border: '1px solid color-mix(in srgb, var(--wa-green) 50%, transparent)' }}>
          Abrir a página do imóvel
        </a>
      </div>
    </div>
  )
}
