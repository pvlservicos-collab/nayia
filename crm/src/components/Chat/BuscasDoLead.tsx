'use client'

/**
 * AS BUSCAS DO LEAD NO CARD (Pedro, 28/10/2026): "ver se tem algum dos nossos imóveis que faz sentido enviar para esses
 * leads, é claro que ainda não foi enviado, e deixar salvo essas buscas do lead como um cardzinho no contato deles no
 * menu da direita do contato aberto". Cada pedido que ele fez vira uma caixa com a manchete, o que ele disse e os
 * nossos imóveis com a nota da Captação ativa (a mesma régua dos pedidos dos grupos); clicar no imóvel abre o porquê.
 * Lê /api/leads/{id}/buscas (nayia 510). Sem busca salva, o card não aparece.
 */
import { useCallback, useEffect, useState } from 'react'
import { ArrowsClockwise, CaretDown, CaretRight, CircleNotch, MagnifyingGlass } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS } from '@/lib/fusoDeManaus'

interface ItemDaNota { criterio: string; texto: string; peso: number | null; pontos: number | null }
interface ImovelDaBusca {
  codigo: number; nota: number; detalhe: ItemDaNota[]; condominio: string | null; bairro: string | null
  tipo: string | null; quartos: number | null; venda: number | null; aluguel: number | null; enviado: boolean
}
interface Busca {
  id: number; titulo: string; disse: string | null; situacao: 'com_opcoes' | 'sem_opcoes' | 'abaixo_do_minimo'
  motivo: string | null; analisada_em: string; imoveis: ImovelDaBusca[]
}

const VERDE = 90   // os cortes da nota da Captação ativa (nay-grupos/config.json)

function reais(v: number | null): string {
  return v == null ? '' : 'R$ ' + Math.round(Number(v)).toLocaleString('pt-BR')
}

function corDaNota(nota: number): string {
  return nota >= VERDE ? 'var(--wa-green)' : '#d97706'
}

function Imovel({ i, venda }: { i: ImovelDaBusca; venda: boolean }) {
  const [aberto, setAberto] = useState(false)
  const preco = venda ? i.venda : i.aluguel
  return (
    <li className="rounded-lg" style={{ border: '1px solid var(--wa-divider)' }}>
      <button type="button" onClick={() => setAberto((a) => !a)}
              className="w-full flex items-center gap-2 px-2.5 py-2 text-left" title="Por que essa nota">
        <span className="shrink-0 inline-flex items-center justify-center w-9 h-6 rounded-md text-[12px] font-bold"
              style={{ background: `color-mix(in srgb, ${corDaNota(i.nota)} 16%, transparent)`, color: corDaNota(i.nota) }}>
          {Math.round(i.nota)}
        </span>
        <span className="min-w-0 flex-1 text-[12.5px] leading-4" style={{ color: 'var(--wa-text)' }}>
          <b>#{i.codigo}</b> {i.condominio || i.tipo} · {i.bairro}
          <span className="block" style={{ color: 'var(--wa-text-2)' }}>
            {[i.quartos ? `${i.quartos} quarto${i.quartos > 1 ? 's' : ''}` : null, reais(preco)].filter(Boolean).join(' · ')}
          </span>
        </span>
        {i.enviado && (
          <span className="shrink-0 rounded-full px-2 py-[2px] text-[11px]"
                style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text-2)' }}>já enviado</span>
        )}
        {aberto ? <CaretDown size={13} /> : <CaretRight size={13} />}
      </button>
      {aberto && (
        <ul className="px-2.5 pb-2 space-y-0.5 text-[11.5px] leading-4" style={{ color: 'var(--wa-text-2)' }}>
          {i.detalhe.map((d, n) => (
            <li key={n}>• {d.texto}{d.pontos != null && d.peso != null ? ` (${d.pontos} de ${d.peso})` : ''}</li>
          ))}
        </ul>
      )}
    </li>
  )
}

export default function BuscasDoLead({ leadId }: { leadId: string }) {
  const [buscas, setBuscas] = useState<Busca[] | null>(null)
  const [carregando, setCarregando] = useState(false)

  const ler = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/leads/${leadId}/buscas`)
      if (r.ok) setBuscas((await r.json()).buscas || [])
    } finally {
      setCarregando(false)
    }
  }, [leadId])

  useEffect(() => { setBuscas(null); void ler() }, [ler])

  if (!buscas?.length) return null
  const quando = new Date(buscas[0].analisada_em).toLocaleDateString('pt-BR', { timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit' })
  return (
    <section className="px-4 py-3.5" style={{ background: 'var(--wa-panel)' }}>
      <div className="flex items-center justify-between gap-2 mb-2">
        <h3 className="text-[13px] flex items-center gap-1.5" style={{ color: 'var(--wa-text-2)' }}>
          <MagnifyingGlass size={14} /> Buscas do lead <span className="text-[11.5px]">(análise de {quando})</span>
        </h3>
        <button type="button" onClick={() => void ler()} className="wa-icone-btn !w-7 !h-7" title="Ler de novo" aria-label="Ler de novo">
          {carregando ? <CircleNotch size={14} className="animate-spin" /> : <ArrowsClockwise size={14} />}
        </button>
      </div>
      <div className="space-y-3">
        {buscas.map((b) => {
          const venda = b.titulo.startsWith('VENDA')
          return (
            <div key={b.id} className="rounded-xl p-2.5" style={{ border: '1px solid var(--wa-divider)' }}>
              <p className="text-[12.5px] font-semibold leading-4" style={{ color: 'var(--wa-text)' }}>{b.titulo}</p>
              {b.disse && <p className="text-[11.5px] leading-4 mt-1" style={{ color: 'var(--wa-text-2)' }}>“{b.disse}”</p>}
              {b.imoveis.length > 0 ? (
                <ul className="mt-2 space-y-1.5">
                  {b.imoveis.map((i) => <Imovel key={i.codigo} i={i} venda={venda} />)}
                </ul>
              ) : (
                <p className="text-[12px] mt-2" style={{ color: b.situacao === 'abaixo_do_minimo' ? 'var(--wa-tag-tel)' : 'var(--wa-text-2)' }}>
                  {b.situacao === 'com_opcoes' ? 'Os imóveis que serviam saíram do mercado.' : `Nenhum nosso para mandar: ${b.motivo || 'sem opção'}.`}
                </p>
              )}
            </div>
          )
        })}
      </div>
    </section>
  )
}
