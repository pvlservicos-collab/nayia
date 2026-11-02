'use client'

/**
 * AS OPÇÕES NOTA 90+ DA BUSCA DO LEAD (Pedro, 01/11/2026): "embaixo do card grupos a Nay deve entender as solicitações
 * do lead e já deixar umas opções de imóveis que sejam 90 ou mais de nota; se o imóvel já foi mandado ele fica com borda
 * vermelha, se não, verde, como um quadradinho; quando passa o mouse abre um pequeno popup mostrando o imóvel, fotos em
 * cima e informações embaixo ... as fotos podem ser para passar para o lado só mostrando a primeira".
 *
 * Os imóveis vêm da própria análise do pedido (privado.lead_busca, a nota da Captação ativa: nay-olx/olx/busca_do_lead.py
 * refaz quando o pedido muda) e o "já enviado" é conferido na hora (crm_lead_buscas). O popup lê o card e as fotos do
 * imóvel só quando abre (/api/imoveis-nay/card/{código}?cliente=1) e guarda para a próxima vez. No celular, tocar abre.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { CaretLeft, CaretRight, CircleNotch } from '@phosphor-icons/react'

export interface OpcaoDaBusca {
  codigo: number; nota: number; condominio: string | null; bairro: string | null; tipo: string | null
  quartos: number | null; venda: number | null; aluguel: number | null; enviado: boolean
}

interface CardDoImovel {
  fotos: string[]
  imovel: { condominio: string | null; bairro: string | null; tipo: string | null; quartos: number | null; suites: number | null
    vagas: number | null; area_total: number | null; valor_venda: number | null; valor_aluguel: number | null; status: string | null }
}

export const NOTA_MINIMA = 90
const VERDE = 'var(--wa-green)'
const VERMELHO = '#dc2626'
const LARGURA = 232
const cache = new Map<number, CardDoImovel | null>()

function reais(v: number | null | undefined): string | null {
  return v == null || !Number(v) ? null : 'R$ ' + Math.round(Number(v)).toLocaleString('pt-BR')
}

function Popup({ o, x, y, embaixo, aoEntrar, aoSair }: {
  o: OpcaoDaBusca; x: number; y: number; embaixo: boolean; aoEntrar: () => void; aoSair: () => void
}) {
  const [card, setCard] = useState<CardDoImovel | null | undefined>(cache.get(o.codigo))
  const [n, setN] = useState(0)
  useEffect(() => {
    setN(0)
    if (cache.has(o.codigo)) { setCard(cache.get(o.codigo)); return }
    let vivo = true
    setCard(undefined)
    fetch(`/api/imoveis-nay/card/${o.codigo}?cliente=1`).then((r) => r.ok ? r.json() : null).catch(() => null)
      .then((j) => { cache.set(o.codigo, j); if (vivo) setCard(j) })
    return () => { vivo = false }
  }, [o.codigo])
  const fotos = card?.fotos || []
  const i = card?.imovel
  const preco = [reais(i?.valor_aluguel ?? o.aluguel) && `Aluguel ${reais(i?.valor_aluguel ?? o.aluguel)}`,
                 reais(i?.valor_venda ?? o.venda) && `Venda ${reais(i?.valor_venda ?? o.venda)}`].filter(Boolean).join(' · ')
  const passar = (d: number) => setN((k) => (k + d + fotos.length) % fotos.length)
  return (
    <div onMouseEnter={aoEntrar} onMouseLeave={aoSair} role="dialog" aria-label={`Imóvel ${o.codigo}`}
         className="fixed z-[90] rounded-xl overflow-hidden shadow-xl"
         style={{ left: x, top: y, width: LARGURA, transform: embaixo ? undefined : 'translateY(-100%)',
                  background: 'var(--wa-panel)', border: `1.5px solid ${o.enviado ? VERMELHO : VERDE}` }}>
      <div className="relative w-full h-[140px]" style={{ background: 'var(--wa-divider)' }}>
        {card === undefined ? (
          <span className="absolute inset-0 flex items-center justify-center"><CircleNotch size={20} className="animate-spin" /></span>
        ) : fotos.length ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={fotos[n]} alt={`Foto ${n + 1} do ${o.codigo}`} className="w-full h-full object-cover" />
            {fotos.length > 1 && (
              <>
                <button type="button" onClick={() => passar(-1)} aria-label="Foto anterior"
                        className="absolute left-1 top-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-black/55 text-white flex items-center justify-center">
                  <CaretLeft size={15} weight="bold" />
                </button>
                <button type="button" onClick={() => passar(1)} aria-label="Próxima foto"
                        className="absolute right-1 top-1/2 -translate-y-1/2 w-7 h-7 rounded-full bg-black/55 text-white flex items-center justify-center">
                  <CaretRight size={15} weight="bold" />
                </button>
                <span className="absolute right-1.5 bottom-1.5 rounded-full px-1.5 text-[10.5px] bg-black/55 text-white">{n + 1}/{fotos.length}</span>
              </>
            )}
          </>
        ) : (
          <span className="absolute inset-0 flex items-center justify-center text-[12px]" style={{ color: 'var(--wa-text-2)' }}>sem fotos</span>
        )}
      </div>
      <div className="px-2.5 py-2 text-[12px] leading-4" style={{ color: 'var(--wa-text)' }}>
        <p className="font-semibold"><span style={{ color: o.enviado ? VERMELHO : VERDE }}>#{o.codigo}</span> {i?.condominio || o.condominio || i?.tipo || o.tipo}</p>
        <p style={{ color: 'var(--wa-text-2)' }}>{i?.bairro || o.bairro}</p>
        <p className="mt-0.5">{[i?.quartos ?? o.quartos ? `${i?.quartos ?? o.quartos} quartos` : null,
                                i?.suites ? `${i.suites} suíte${i.suites > 1 ? 's' : ''}` : null,
                                i?.vagas ? `${i.vagas} vaga${i.vagas > 1 ? 's' : ''}` : null,
                                i?.area_total ? `${Math.round(Number(i.area_total))} m²` : null].filter(Boolean).join(' · ')}</p>
        {preco && <p className="font-semibold mt-0.5">{preco}</p>}
        <p className="mt-0.5" style={{ color: 'var(--wa-text-2)' }}>
          nota {Math.round(o.nota)} · {o.enviado ? 'já enviado ao lead' : 'ainda não enviado'}
        </p>
      </div>
    </div>
  )
}

export default function OpcoesNota90({ imoveis }: { imoveis: OpcaoDaBusca[] }) {
  const [aberto, setAberto] = useState<{ o: OpcaoDaBusca; x: number; y: number; embaixo: boolean } | null>(null)
  const fechar = useRef<ReturnType<typeof setTimeout> | null>(null)
  // a melhor nota de cada imóvel (o mesmo imóvel pode servir a dois pedidos), da maior para a menor
  const melhores = new Map<number, OpcaoDaBusca>()
  for (const i of imoveis) if (i.nota >= NOTA_MINIMA && (melhores.get(i.codigo)?.nota ?? -1) < i.nota) melhores.set(i.codigo, i)
  const lista = [...melhores.values()].sort((a, b) => b.nota - a.nota)

  const segurar = useCallback(() => { if (fechar.current) clearTimeout(fechar.current) }, [])
  const soltar = useCallback(() => { segurar(); fechar.current = setTimeout(() => setAberto(null), 180) }, [segurar])
  const abrir = (o: OpcaoDaBusca, el: HTMLElement) => {
    segurar()
    const r = el.getBoundingClientRect()
    const x = Math.min(Math.max(8, r.left + r.width / 2 - LARGURA / 2), window.innerWidth - LARGURA - 8)
    const embaixo = r.top < 300            // perto do alto da tela: abre para baixo
    setAberto({ o, x, y: embaixo ? r.bottom + 6 : r.top - 6, embaixo })
  }
  useEffect(() => () => segurar(), [segurar])

  return (
    <div className="mt-3">
      <p className="text-[11.5px] font-semibold uppercase tracking-wide" style={{ color: 'var(--wa-text-2)' }}>
        Opções nota {NOTA_MINIMA}+ ({lista.length})
      </p>
      {lista.length ? (
        <>
          <ul className="mt-1.5 flex flex-wrap gap-1.5">
            {lista.map((o) => (
              <li key={o.codigo}>
                <button type="button"
                        onMouseEnter={(e) => abrir(o, e.currentTarget)} onMouseLeave={soltar}
                        onClick={(e) => (aberto?.o.codigo === o.codigo ? setAberto(null) : abrir(o, e.currentTarget))}
                        className="w-[58px] h-[46px] rounded-lg flex flex-col items-center justify-center leading-none"
                        style={{ border: `2px solid ${o.enviado ? VERMELHO : VERDE}`, background: 'var(--wa-panel)', color: 'var(--wa-text)' }}
                        aria-label={`Imóvel ${o.codigo}, nota ${Math.round(o.nota)}${o.enviado ? ', já enviado' : ''}`}>
                  <span className="text-[12px] font-bold">#{o.codigo}</span>
                  <span className="text-[10.5px] mt-1" style={{ color: o.enviado ? VERMELHO : VERDE }}>{Math.round(o.nota)}</span>
                </button>
              </li>
            ))}
          </ul>
          <p className="text-[11px] mt-1.5" style={{ color: 'var(--wa-text-2)' }}>
            <span style={{ color: VERDE }}>■</span> ainda não enviado · <span style={{ color: VERMELHO }}>■</span> já enviado ao lead
          </p>
        </>
      ) : (
        <p className="text-[12px] mt-1" style={{ color: 'var(--wa-text-2)' }}>Nenhum imóvel nosso com nota {NOTA_MINIMA} ou mais para este pedido agora.</p>
      )}
      {aberto && <Popup o={aberto.o} x={aberto.x} y={aberto.y} embaixo={aberto.embaixo} aoEntrar={segurar} aoSair={soltar} />}
    </div>
  )
}
