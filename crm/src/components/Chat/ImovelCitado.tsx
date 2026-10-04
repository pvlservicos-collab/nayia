'use client'

/**
 * O imóvel da mensagem que o corretor MARCOU.
 *
 * Tel, 27/09/2026: "se alguem marcar ma mensagem de um imovel disparado no
 * grupo vai aparecer encima da mensagem um popup com o imovel".
 *
 * COMO ELE DESCOBRE QUAL IMÓVEL É, em ordem:
 *   1. um "Código: 3050" no texto citado ou no próprio texto da mensagem;
 *   2. o id da mensagem marcada -> a caixa de saída da Nay, que guarda o código
 *      do imóvel de cada envio (`/api/imoveis-nay/mensagem`).
 *
 * O caminho 2 é o que faz isto funcionar com card do GRUPO: a Z-API manda só o
 * id da mensagem marcada, sem o conteúdo, e o card do grupo nem passa pelo CRM.
 * Quem sabe é a caixa de saída.
 *
 * Não descobriu? Não mostra nada. Mostrar o imóvel errado em cima da mensagem
 * seria pior que não mostrar -- alguém negociaria o apartamento errado.
 */
import { useEffect, useState } from 'react'
import { X } from '@phosphor-icons/react'
import { codigosNoTexto } from '@/lib/imovelCodigo'

interface CardDoImovel {
  codigo: number
  card: string
  fotos: string[]
  e_parceiro: boolean
  imovel: {
    status: string | null
    tipo: string | null
    condominio: string | null
    bairro: string | null
    valor_venda: number | null
    valor_aluguel: number | null
    capa: string | null
    total_fotos: number
  }
}

/* Cache por processo: rolar a conversa para cima e para baixo não pode virar uma
   chamada por bolha a cada vez. `null` é resposta também -- significa "já
   perguntei e não é imóvel", e evita repetir a pergunta que deu 404. */
const memoria = new Map<string, CardDoImovel | null>()
const emVoo = new Map<string, Promise<CardDoImovel | null>>()

async function resolver(chave: string, url: string): Promise<CardDoImovel | null> {
  if (memoria.has(chave)) return memoria.get(chave) ?? null
  const jaPedido = emVoo.get(chave)
  if (jaPedido) return jaPedido
  const p = (async () => {
    try {
      const res = await fetch(url)
      if (!res.ok) { memoria.set(chave, null); return null }
      const d = (await res.json()) as CardDoImovel
      memoria.set(chave, d)
      return d
    } catch {
      memoria.set(chave, null)
      return null
    } finally {
      emVoo.delete(chave)
    }
  })()
  emVoo.set(chave, p)
  return p
}

function reais(v: number | null) {
  if (!v) return null
  return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })
}

export default function ImovelCitado({
  quotedText, quotedMessageId, ownText, isOutgoing,
}: {
  quotedText?: string | null
  quotedMessageId?: string | null
  ownText?: string | null
  isOutgoing: boolean
}) {
  const [imovel, setImovel] = useState<CardDoImovel | null>(null)
  const [aberto, setAberto] = useState(false)

  useEffect(() => {
    let vivo = true
    const porTexto = codigosNoTexto(quotedText || '')[0] ?? codigosNoTexto(ownText || '')[0] ?? null
    const chave = porTexto ? `cod:${porTexto}` : (quotedMessageId ? `msg:${quotedMessageId}` : null)
    if (!chave) return
    const url = porTexto
      ? `/api/imoveis-nay/card/${porTexto}`
      : `/api/imoveis-nay/mensagem?id=${encodeURIComponent(quotedMessageId as string)}`
    resolver(chave, url).then((d) => { if (vivo) setImovel(d) })
    return () => { vivo = false }
  }, [quotedText, quotedMessageId, ownText])

  if (!imovel) return null

  const i = imovel.imovel
  const valor = reais(i.valor_aluguel) ? `${reais(i.valor_aluguel)}/mês` : reais(i.valor_venda)
  const fundo = isOutgoing ? 'rgba(0,0,0,0.14)' : 'rgba(255,255,255,0.07)'

  return (
    <>
      <button
        type="button"
        onClick={(e) => { e.stopPropagation(); setAberto(true) }}
        className="w-full text-left rounded-lg mb-1.5 overflow-hidden flex items-stretch gap-2 hover:brightness-110 transition"
        style={{ backgroundColor: fundo }}
        title="Ver o imóvel desta mensagem"
      >
        {i.capa
          ? <img src={i.capa} alt="" className="w-[52px] h-[52px] object-cover flex-shrink-0" />
          : <span className="w-[52px] h-[52px] flex-shrink-0 grid place-items-center text-[10px] opacity-60">sem foto</span>}
        <span className="flex-1 min-w-0 py-1.5 pr-2">
          <span className="block text-[10px] uppercase tracking-wide opacity-70">
            Imóvel desta mensagem · cód. {imovel.codigo}
          </span>
          <span className="block text-[12px] font-semibold truncate">
            {i.condominio || i.tipo || `Imóvel ${imovel.codigo}`}
          </span>
          <span className="block text-[11px] opacity-80 truncate">
            {[i.bairro, valor, i.status].filter(Boolean).join(' · ')}
            {imovel.e_parceiro ? ' · parceiro' : ''}
          </span>
        </span>
      </button>

      {aberto && (
        <div className="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/65"
             onClick={(e) => { e.stopPropagation(); setAberto(false) }}>
          <div onClick={(e) => e.stopPropagation()}
               className="w-full max-w-md bg-panel border border-line rounded-2xl p-4 max-h-[88dvh] overflow-y-auto">
            <div className="flex items-start justify-between gap-3 mb-3">
              <div className="min-w-0">
                <h2 className="text-base font-bold text-ink truncate">
                  {i.condominio || i.tipo || `Imóvel ${imovel.codigo}`}
                </h2>
                <p className="text-xs text-muted">
                  código {imovel.codigo}
                  {i.status ? ` · ${i.status}` : ''}
                  {imovel.e_parceiro ? ' · imóvel de parceiro' : ''}
                </p>
              </div>
              <button type="button" onClick={() => setAberto(false)} aria-label="Fechar" title="Fechar"
                      className="wa-fechar-foto flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center">
                <X size={22} weight="bold" />
              </button>
            </div>

            <pre className="text-[12.5px] text-ink whitespace-pre-wrap break-words font-sans bg-panel-2 border border-line rounded-xl p-3">
{imovel.card}
            </pre>

            {/* A página nova do imóvel (Pedro, 02/10): a mesma que o corretor abre no site.
                Só existe para imóvel disponível e anunciado; fora disso ela mesma avisa. */}
            <a href={`https://imobeasy.online/imovel/${imovel.codigo}`} target="_blank" rel="noreferrer"
               className="mt-3 block text-center text-[12.5px] font-semibold text-ink border border-line rounded-xl py-2 hover:brightness-110 transition">
              Abrir a página do imóvel
            </a>

            {imovel.fotos.length > 0 && (
              <>
                <p className="text-[11px] text-muted mt-3 mb-1">
                  {i.total_fotos} foto{i.total_fotos === 1 ? '' : 's'} no imóvel
                </p>
                <div className="grid grid-cols-3 gap-1.5">
                  {imovel.fotos.slice(0, 9).map((u) => (
                    <a key={u} href={u} target="_blank" rel="noreferrer">
                      <img src={u} alt="" loading="lazy"
                           className="w-full aspect-[4/3] object-cover rounded-lg bg-panel-2" />
                    </a>
                  ))}
                </div>
              </>
            )}
          </div>
        </div>
      )}
    </>
  )
}
