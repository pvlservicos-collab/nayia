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
import OpcoesNota90 from './OpcoesNota90'
import PedirNosGrupos from './PedirNosGrupos'

interface ItemDaNota { criterio: string; texto: string; peso: number | null; pontos: number | null }
interface ImovelDaBusca {
  codigo: number; nota: number; detalhe: ItemDaNota[]; condominio: string | null; bairro: string | null
  tipo: string | null; quartos: number | null; venda: number | null; aluguel: number | null; enviado: boolean
}
interface Busca {
  id: number; titulo: string; disse: string | null; situacao: 'com_opcoes' | 'sem_opcoes' | 'abaixo_do_minimo'
  motivo: string | null; analisada_em: string; imoveis: ImovelDaBusca[]
}
interface PedidoNoGrupo {
  grupo: string; nome?: string; em?: string; teste?: boolean; repeticao?: boolean; encerrou?: boolean
  manual?: boolean; quem?: string     // 01/11 (558): pedido à mão no CRM, pelo número da Parceria
}
interface Anunciante { anunciante?: string; titulo?: string; preco?: number; bairro?: string; em?: string; teste?: boolean }
interface Corretor { nome: string | null; telefone: string; estado: string; codigo: number | null; origem: string | null; em: string }
interface Oferta { nome?: string; tel?: string; codigo?: number; estado?: string; em?: string; de?: string }
interface Passo { em: string; lugar: string; texto: string }
interface BuscaAtiva {
  id: number; estado: string; motivo: string | null; teste: boolean; ativada_em: string | null; atualizado_em: string
  grupos: PedidoNoGrupo[]; olx: Anunciante[]; ofertas: Oferta[]; corretores: Corretor[]; passos: Passo[]
}

const META_DE_OPCOES = 5   // Pedro, 29/10: no mínimo 5 opções para cada lead (nay-olx OPCOES_META)
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

type PassoDoResumo = { rotulo: string; estado: 'feito' | 'andando' | 'espera'; texto: string; aviso?: string }

/**
 * O RESUMO EM ETAPAS (Pedro, 29/10/2026: "ta ruim de visualizar essas buscas, preciso no card de cada lead um resumo em
 * etapas de onde esta a busca dele, quantos imoveis achamos de cada fonte, se a IA ja mandou msg nos grupos, ou para os
 * corretores"). Uma linha por etapa, com a bolinha (feita, andando, esperando) e o número de cada fonte; no fim, quantas
 * opções o cliente já recebeu da meta de cinco.
 */
function ResumoDaBusca({ buscas, a }: { buscas: Busca[]; a: BuscaAtiva | null }) {
  const nossos = buscas.flatMap((b) => b.imoveis)
  const codigosNossos = new Set(nossos.map((i) => i.codigo))
  const enviadosDaBase = new Set(nossos.filter((i) => i.enviado).map((i) => i.codigo))
  const msgsGrupos = (a?.grupos || []).filter((g) => !g.encerrou)
  const gruposDistintos = new Set(msgsGrupos.map((g) => g.grupo)).size
  const grupoTeste = msgsGrupos.some((g) => g.teste)
  const olx = a?.olx || []
  const corretores = a?.corretores || []
  const comImovel = corretores.filter((c) => c.codigo).length
  // o que o cliente já recebeu: os da base marcados como enviados + as ofertas que saíram para ele
  const chegouAoCliente = new Set<number>(enviadosDaBase)
  for (const o of a?.ofertas || []) if (o.codigo && (o.estado === 'cliente' || o.estado === 'grupo')) chegouAoCliente.add(o.codigo)
  const recebidas = chegouAoCliente.size
  const buscando = a?.estado === 'buscando'
  const fora = !!a && a.estado !== 'perfil' && a.estado !== 'nossa_base'

  const passos: PassoDoResumo[] = [
    { rotulo: 'Pedido', estado: a && a.estado === 'perfil' ? 'andando' : 'feito',
      texto: a?.estado === 'perfil' ? 'ainda montando o pedido' : 'pedido entendido' },
    { rotulo: 'Nossa base', estado: nossos.length || fora ? 'feito' : 'espera',
      texto: nossos.length ? `${nossos.length} imóve${nossos.length > 1 ? 'is' : 'l'} nosso${nossos.length > 1 ? 's' : ''} · ${enviadosDaBase.size} já enviado${enviadosDaBase.size === 1 ? '' : 's'}` : 'nenhum nosso no perfil' },
    { rotulo: 'Grupos', estado: msgsGrupos.length ? 'feito' : buscando ? 'andando' : 'espera',
      texto: msgsGrupos.length ? `a IA mandou ${msgsGrupos.length} mensagem${msgsGrupos.length > 1 ? 'ns' : ''} em ${gruposDistintos} grupo${gruposDistintos > 1 ? 's' : ''}${grupoTeste ? ' (teste)' : ''}`
        : buscando ? 'a mandar' : 'ainda não mandou' },
    { rotulo: 'OLX', estado: olx.length ? 'feito' : buscando ? 'andando' : 'espera',
      texto: olx.length ? `${olx.length} anunciante${olx.length > 1 ? 's' : ''} perguntado${olx.length > 1 ? 's' : ''}` : buscando ? 'a procurar' : 'ainda não perguntou' },
    { rotulo: 'Corretores', estado: corretores.length ? 'feito' : buscando ? 'andando' : 'espera',
      texto: corretores.length ? `${corretores.length} respondeu${corretores.length > 1 ? 'ram' : ''} · ${comImovel} com imóvel` : 'ninguém respondeu ainda' },
    { rotulo: 'Opções ao cliente', estado: recebidas >= META_DE_OPCOES ? 'feito' : recebidas ? 'andando' : 'espera',
      texto: `${Math.min(recebidas, 99)} de ${META_DE_OPCOES}`,
      aviso: recebidas >= META_DE_OPCOES ? undefined : `faltam ${META_DE_OPCOES - recebidas}` },
  ]
  const cor = (e: PassoDoResumo['estado']) => e === 'feito' ? 'var(--wa-green)' : e === 'andando' ? '#d97706' : 'var(--wa-divider)'
  void codigosNossos
  return (
    <ol className="mb-3 space-y-0" aria-label="Etapas da busca">
      {passos.map((p, n) => (
        <li key={p.rotulo} className="flex gap-2.5">
          <span className="flex flex-col items-center">
            <span className="mt-[3px] w-[11px] h-[11px] rounded-full shrink-0"
                  style={{ background: p.estado === 'espera' ? 'transparent' : cor(p.estado), border: `2px solid ${cor(p.estado)}` }} />
            {n < passos.length - 1 && <span className="w-[2px] flex-1 min-h-[12px]" style={{ background: 'var(--wa-divider)' }} />}
          </span>
          <span className="pb-1.5 text-[12.5px] leading-4 min-w-0" style={{ color: 'var(--wa-text)' }}>
            <b>{p.rotulo}</b>
            <span style={{ color: p.estado === 'espera' ? 'var(--wa-text-2)' : 'var(--wa-text)' }}> · {p.texto}</span>
            {p.aviso && <span className="ml-1 font-semibold" style={{ color: '#d97706' }}>({p.aviso})</span>}
          </span>
        </li>
      ))}
    </ol>
  )
}

function Andamento({ a, depoisDosGrupos }: { a: BuscaAtiva; depoisDosGrupos?: React.ReactNode }) {
  const [etapas, setEtapas] = useState(false)
  const sit = SITUACAO[a.estado] || { rotulo: a.estado, cor: 'var(--wa-text-2)' }
  // os pedidos de cada grupo: quantas vezes foi, o último e se parou (3 pedidos sem imóvel, 29/10)
  const grupos = useMemo(() => {
    const m = new Map<string, { nome: string; vezes: number; ultimo: string; parou: boolean; teste: boolean; mao: number }>()
    for (const g of a.grupos || []) {
      const x = m.get(g.grupo) || { nome: g.nome || g.grupo, vezes: 0, ultimo: '', parou: false, teste: !!g.teste, mao: 0 }
      if (g.encerrou) x.parou = true
      else { x.vezes += 1; x.ultimo = g.em || x.ultimo; x.parou = false; if (g.manual) x.mao += 1 }
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
              {g.vezes}×{g.mao ? ` (${g.mao} à mão)` : ''} · {quando(g.ultimo)}{g.parou ? ' · parou' : ''}{g.teste ? ' · teste' : ''}
            </span>
          </li>
        ))}
      </Bloco>
      {depoisDosGrupos}
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

  // 01/11 (Pedro): o pedido nos grupos pela Parceria e as opções nota 90+ ficam logo embaixo dos grupos da busca;
  // sem busca ativa, no fim do card (que aparece mesmo sem busca nenhuma, para o pedido nos grupos)
  const nossos = (buscas || []).flatMap((b) => b.imoveis)
  const extra = (
    <>
      <PedirNosGrupos leadId={leadId} aoEnviar={() => void ler()} />
      {(buscas || []).length > 0 && <OpcoesNota90 imoveis={nossos} />}
    </>
  )
  if (buscas === null && !ativa) return null
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
        {(buscas?.length || ativa) ? <ResumoDaBusca buscas={buscas || []} a={ativa} /> : null}
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
          {ativa ? <Andamento a={ativa} depoisDosGrupos={extra} /> : extra}
        </div>
      </div>
    </section>
  )
}
