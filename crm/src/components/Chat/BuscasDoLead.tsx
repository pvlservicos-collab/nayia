'use client'

/**
 * AS BUSCAS DO LEAD NO CARD (Pedro, 28/10/2026): "ver se tem algum dos nossos imóveis que faz sentido enviar para esses
 * leads, é claro que ainda não foi enviado, e deixar salvo essas buscas do lead como um cardzinho no contato deles no
 * menu da direita do contato aberto". Cada pedido que ele fez vira uma caixa com a manchete, o que ele disse e os
 * nossos imóveis com a nota da Captação ativa (a mesma régua dos pedidos dos grupos); clicar no imóvel abre o porquê.
 *
 * 29/10 (Pedro): "quero que o card de busca do lead esteja em mais destaque no card do lead e que a Nay atualize a
 * busca ... cada mensagem do lead sobrescreve a antiga" e "embaixo desse card de busca inicial dele se ele tá fazendo a
 * busca e para quais contatos perguntou e as etapas da busca para esse lead". O card sobe no painel, com borda e título
 * fortes; o pedido é o de agora (o nay-olx refaz a análise quando o perfil muda, busca_do_lead.py); embaixo, a busca
 * ativa (nayia 521): em que pé está, os grupos, os anunciantes da OLX, os corretores, as ofertas e as etapas.
 * Lê /api/leads/{id}/buscas. Sem busca nenhuma, o card não aparece.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
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
interface PedidoNoGrupo { grupo: string; nome?: string; em?: string; teste?: boolean; repeticao?: boolean; encerrou?: boolean }
interface Anunciante { anunciante?: string; titulo?: string; preco?: number; bairro?: string; em?: string; teste?: boolean }
interface Corretor { nome: string | null; telefone: string; estado: string; codigo: number | null; origem: string | null; em: string }
interface Oferta { nome?: string; tel?: string; codigo?: number; estado?: string; em?: string }
interface Passo { em: string; lugar: string; texto: string }
interface BuscaAtiva {
  id: number; estado: string; motivo: string | null; teste: boolean; ativada_em: string | null; atualizado_em: string
  grupos: PedidoNoGrupo[]; olx: Anunciante[]; ofertas: Oferta[]; corretores: Corretor[]; passos: Passo[]
}

const VERDE = 90   // os cortes da nota da Captação ativa (nay-grupos/config.json)
const COR = '#0891b2'

/** Em que pé está a busca (privado.busca_cliente.estado, nay-olx/olx/buscas.py). */
const SITUACAO: Record<string, { rotulo: string; cor: string }> = {
  perfil: { rotulo: 'Montando o pedido', cor: 'var(--wa-text-2)' },
  nossa_base: { rotulo: 'Olhando a nossa base', cor: '#2563eb' },
  buscando: { rotulo: 'Buscando fora', cor: 'var(--wa-green)' },
  ofertado: { rotulo: 'Opções enviadas', cor: 'var(--wa-green)' },
  encerrada: { rotulo: 'Encerrada', cor: 'var(--wa-tag-tel)' },
}

/** O nome de cada lugar das etapas, como a equipe fala. */
const LUGAR: Record<string, string> = {
  perfil: 'Pedido', base: 'Nossa base', cliente: 'Cliente', grupos: 'Grupos', olx: 'OLX', corretor: 'Corretor',
  oferta: 'Oferta', equipe: 'Equipe', encerrada: 'Fim',
}

function reais(v: number | null | undefined): string {
  return v == null ? '' : 'R$ ' + Math.round(Number(v)).toLocaleString('pt-BR')
}

function quando(iso: string | null | undefined): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString('pt-BR', { timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}

function corDaNota(nota: number): string {
  return nota >= VERDE ? 'var(--wa-green)' : '#d97706'
}

function Imovel({ i, venda }: { i: ImovelDaBusca; venda: boolean }) {
  const [aberto, setAberto] = useState(false)
  const preco = venda ? i.venda : i.aluguel
  return (
    <li className="rounded-lg" style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-panel)' }}>
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

/** Um bloco de "para quem perguntou", com o título e a contagem. */
function Bloco({ titulo, n, children }: { titulo: string; n: number; children: React.ReactNode }) {
  if (!n) return null
  return (
    <div className="mt-2">
      <p className="text-[11.5px] font-semibold uppercase tracking-wide" style={{ color: 'var(--wa-text-2)' }}>{titulo} ({n})</p>
      <ul className="mt-1 space-y-1 text-[12px] leading-4" style={{ color: 'var(--wa-text)' }}>{children}</ul>
    </div>
  )
}

function Andamento({ a }: { a: BuscaAtiva }) {
  const [etapas, setEtapas] = useState(false)
  const sit = SITUACAO[a.estado] || { rotulo: a.estado, cor: 'var(--wa-text-2)' }
  // os pedidos de cada grupo: quantas vezes foi, o último e se parou (3 pedidos sem imóvel, 29/10)
  const grupos = useMemo(() => {
    const m = new Map<string, { nome: string; vezes: number; ultimo: string; parou: boolean; teste: boolean }>()
    for (const g of a.grupos || []) {
      const x = m.get(g.grupo) || { nome: g.nome || g.grupo, vezes: 0, ultimo: '', parou: false, teste: !!g.teste }
      if (g.encerrou) x.parou = true
      else { x.vezes += 1; x.ultimo = g.em || x.ultimo; x.parou = false }
      m.set(g.grupo, x)
    }
    return [...m.values()].sort((p, q) => (q.ultimo || '').localeCompare(p.ultimo || ''))
  }, [a.grupos])
  return (
    <div className="mt-3 pt-3" style={{ borderTop: '1px dashed var(--wa-divider)' }}>
      <div className="flex items-center gap-2 flex-wrap">
        <span className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-[3px] text-[12px] font-semibold"
              style={{ background: `color-mix(in srgb, ${sit.cor} 14%, transparent)`, color: sit.cor }}>
          <span className="w-2 h-2 rounded-full" style={{ background: sit.cor }} />{sit.rotulo}
        </span>
        {a.teste && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>em teste</span>}
        {a.ativada_em && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>ativada {quando(a.ativada_em)}</span>}
      </div>
      {a.estado === 'encerrada' && a.motivo && (
        <p className="text-[12px] mt-1" style={{ color: 'var(--wa-tag-tel)' }}>{a.motivo}</p>
      )}

      <Bloco titulo="Grupos" n={grupos.length}>
        {grupos.map((g) => (
          <li key={g.nome} className="flex items-center gap-1.5">
            <span className="truncate flex-1">{g.nome}</span>
            <span className="shrink-0 text-[11px]" style={{ color: 'var(--wa-text-2)' }}>
              {g.vezes}× · {quando(g.ultimo)}{g.parou ? ' · parou' : ''}{g.teste ? ' · teste' : ''}
            </span>
          </li>
        ))}
      </Bloco>
      <Bloco titulo="Anunciantes da OLX" n={(a.olx || []).length}>
        {(a.olx || []).map((o, n) => (
          <li key={n}>
            <b>{o.anunciante || 'Anunciante'}</b> · {o.titulo ? o.titulo.slice(0, 60) : 'anúncio'}
            <span style={{ color: 'var(--wa-text-2)' }}> · {[reais(o.preco), o.bairro, quando(o.em)].filter(Boolean).join(' · ')}</span>
          </li>
        ))}
      </Bloco>
      <Bloco titulo="Corretores que responderam" n={(a.corretores || []).length}>
        {(a.corretores || []).map((c, n) => (
          <li key={n}>
            <b>{c.nome || c.telefone}</b>
            <span style={{ color: 'var(--wa-text-2)' }}> · {[c.estado, c.codigo ? `#${c.codigo}` : null, c.origem, quando(c.em)].filter(Boolean).join(' · ')}</span>
          </li>
        ))}
      </Bloco>
      <Bloco titulo="Ofertas" n={(a.ofertas || []).length}>
        {(a.ofertas || []).map((o, n) => (
          <li key={n}>
            {o.codigo ? <b>#{o.codigo}</b> : null} {o.nome || ''}
            <span style={{ color: 'var(--wa-text-2)' }}> · {[o.estado, quando(o.em)].filter(Boolean).join(' · ')}</span>
          </li>
        ))}
      </Bloco>
      {!grupos.length && !(a.olx || []).length && !(a.corretores || []).length && (
        <p className="text-[12px] mt-2" style={{ color: 'var(--wa-text-2)' }}>Ainda não perguntou a ninguém de fora.</p>
      )}

      {(a.passos || []).length > 0 && (
        <div className="mt-2">
          <button type="button" onClick={() => setEtapas((e) => !e)}
                  className="inline-flex items-center gap-1 text-[12px] font-semibold" style={{ color: COR }}>
            {etapas ? <CaretDown size={13} /> : <CaretRight size={13} />} Etapas da busca ({a.passos.length})
          </button>
          {etapas && (
            <ol className="mt-1.5 space-y-1 text-[11.5px] leading-4">
              {a.passos.map((p, n) => (
                <li key={n} className="flex gap-2">
                  <span className="shrink-0 w-[74px] tabular-nums" style={{ color: 'var(--wa-text-2)' }}>{quando(p.em)}</span>
                  <span style={{ color: 'var(--wa-text)' }}>
                    <b style={{ color: COR }}>{LUGAR[p.lugar] || p.lugar}</b> · {p.texto}
                  </span>
                </li>
              ))}
            </ol>
          )}
        </div>
      )}
    </div>
  )
}

export default function BuscasDoLead({ leadId }: { leadId: string }) {
  const [buscas, setBuscas] = useState<Busca[] | null>(null)
  const [ativa, setAtiva] = useState<BuscaAtiva | null>(null)
  const [carregando, setCarregando] = useState(false)

  const ler = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/leads/${leadId}/buscas`)
      if (r.ok) {
        const j = await r.json()
        setBuscas(j.buscas || [])
        setAtiva(j.ativa || null)
      }
    } finally {
      setCarregando(false)
    }
  }, [leadId])

  useEffect(() => { setBuscas(null); setAtiva(null); void ler() }, [ler])

  if (!buscas?.length && !ativa) return null
  return (
    <section className="px-4 py-3.5" style={{ background: 'var(--wa-panel)' }}>
      <div className="rounded-xl p-3" style={{ border: `1.5px solid ${COR}`, background: `color-mix(in srgb, ${COR} 6%, var(--wa-panel))` }}>
        <div className="flex items-center justify-between gap-2 mb-2">
          <h3 className="text-[15px] font-bold flex items-center gap-1.5" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>
            <MagnifyingGlass size={17} weight="bold" style={{ color: COR }} /> Busca do lead
          </h3>
          <button type="button" onClick={() => void ler()} className="wa-icone-btn !w-7 !h-7" title="Ler de novo" aria-label="Ler de novo">
            {carregando ? <CircleNotch size={14} className="animate-spin" /> : <ArrowsClockwise size={14} />}
          </button>
        </div>
        <div className="space-y-3">
          {(buscas || []).map((b) => {
            const venda = b.titulo.startsWith('VENDA')
            return (
              <div key={b.id}>
                <p className="text-[14px] font-semibold leading-5" style={{ color: 'var(--wa-text)' }}>{b.titulo}</p>
                {b.disse && <p className="text-[12px] leading-4 mt-1" style={{ color: 'var(--wa-text-2)' }}>{b.disse}</p>}
                <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>atualizada {quando(b.analisada_em)}</p>
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
          {ativa && <Andamento a={ativa} />}
        </div>
      </div>
    </section>
  )
}
