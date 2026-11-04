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
import { useModoV3 } from '@/lib/modoV3'
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

/** Uma seção que começa fechada: o título com a contagem abre e fecha (Pedro, 02/11: "coisas que não precisam estar abertas desde o começo"). */
function Secao({ titulo, n, children, aberta = false }: { titulo: string; n: number | string; children: React.ReactNode; aberta?: boolean }) {
  const [aberto, setAberto] = useState(aberta)
  return (
    <div className="border-t first:border-t-0" style={{ borderColor: 'var(--wa-divider)' }}>
      <button type="button" onClick={() => setAberto((a) => !a)} aria-expanded={aberto}
              className="w-full flex items-center gap-1.5 py-2 text-left text-[12.5px] font-semibold" style={{ color: 'var(--wa-text)' }}>
        {aberto ? <CaretDown size={13} /> : <CaretRight size={13} />}
        <span className="flex-1">{titulo}</span>
        <span className="rounded-full px-1.5 min-w-[22px] text-center text-[11px]"
              style={{ background: 'var(--wa-row-selected)', color: 'var(--wa-text-2)' }}>{n}</span>
      </button>
      {aberto && <div className="pb-2.5">{children}</div>}
    </div>
  )
}

type PassoDoResumo = { rotulo: string; estado: 'feito' | 'andando' | 'espera'; curto: string; texto: string }

/**
 * O RESUMO EM ETAPAS (Pedro, 29/10/2026: "ta ruim de visualizar essas buscas, preciso no card de cada lead um resumo em
 * etapas de onde esta a busca dele, quantos imoveis achamos de cada fonte, se a IA ja mandou msg nos grupos, ou para os
 * corretores"). 02/11: em quadradinhos, uma linha curta cada, com o texto inteiro ao passar o mouse; no fim, a barra das
 * opções que o cliente já recebeu da meta de cinco.
 */
function ResumoDaBusca({ buscas, a }: { buscas: Busca[]; a: BuscaAtiva | null }) {
  const nossos = buscas.flatMap((b) => b.imoveis)
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
    { rotulo: 'Nossa base', estado: nossos.length || fora ? 'feito' : 'espera',
      curto: nossos.length ? `${nossos.length}${enviadosDaBase.size ? ` · ${enviadosDaBase.size} enviado${enviadosDaBase.size > 1 ? 's' : ''}` : ''}` : 'nenhum',
      texto: nossos.length ? `${nossos.length} imóve${nossos.length > 1 ? 'is' : 'l'} nosso${nossos.length > 1 ? 's' : ''} · ${enviadosDaBase.size} já enviado${enviadosDaBase.size === 1 ? '' : 's'}` : 'nenhum nosso no perfil' },
    { rotulo: 'Grupos', estado: msgsGrupos.length ? 'feito' : buscando ? 'andando' : 'espera',
      curto: msgsGrupos.length ? `${gruposDistintos} grupo${gruposDistintos > 1 ? 's' : ''}${grupoTeste ? ' (teste)' : ''}` : buscando ? 'a mandar' : 'não mandou',
      texto: msgsGrupos.length ? `a IA mandou ${msgsGrupos.length} mensagem${msgsGrupos.length > 1 ? 'ns' : ''} em ${gruposDistintos} grupo${gruposDistintos > 1 ? 's' : ''}${grupoTeste ? ' (teste)' : ''}`
        : buscando ? 'a mandar' : 'ainda não mandou' },
    { rotulo: 'OLX', estado: olx.length ? 'feito' : buscando ? 'andando' : 'espera',
      curto: olx.length ? `${olx.length} perguntado${olx.length > 1 ? 's' : ''}` : buscando ? 'a procurar' : 'não perguntou',
      texto: olx.length ? `${olx.length} anunciante${olx.length > 1 ? 's' : ''} perguntado${olx.length > 1 ? 's' : ''}` : buscando ? 'a procurar' : 'ainda não perguntou' },
    { rotulo: 'Corretores', estado: corretores.length ? 'feito' : buscando ? 'andando' : 'espera',
      curto: corretores.length ? `${corretores.length} · ${comImovel} c/ imóvel` : 'ninguém',
      texto: corretores.length ? `${corretores.length} respondeu${corretores.length > 1 ? 'ram' : ''} · ${comImovel} com imóvel` : 'ninguém respondeu ainda' },
  ]
  const v3 = useModoV3()
  const cor = (e: PassoDoResumo['estado']) => e === 'feito' ? 'var(--wa-green)' : e === 'andando' ? '#d97706' : 'var(--wa-divider)'
  const meta = Math.min(100, Math.round((recebidas / META_DE_OPCOES) * 100))
  const bateu = recebidas >= META_DE_OPCOES
  return (
    <div className="mb-3" aria-label="Etapas da busca">
      <ul className="grid grid-cols-2 gap-1.5">
        {passos.map((p) => (
          <li key={p.rotulo} title={p.texto} className="rounded-lg px-2 py-1.5 leading-4"
              style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-panel)' }}>
            <span className="flex items-center gap-1.5 text-[11px]" style={{ color: 'var(--wa-text-2)' }}>
              <span className={v3 ? 'w-[7px] h-[7px] rounded-full shrink-0' : 'w-[9px] h-[9px] rounded-full shrink-0'}
                    style={{ background: p.estado === 'espera' ? 'transparent' : cor(p.estado), border: `2px solid ${cor(p.estado)}` }} />
              {p.rotulo}
            </span>
            <span className="block text-[12.5px] font-semibold truncate" style={{ color: 'var(--wa-text)' }}>{p.curto}</span>
          </li>
        ))}
      </ul>
      <div className="mt-2" title={`Opções que o cliente já recebeu: ${recebidas} de ${META_DE_OPCOES}`}>
        <div className="flex items-center justify-between text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>
          <span>Opções ao cliente</span>
          <span className="font-semibold" style={{ color: bateu ? 'var(--wa-green)' : '#d97706' }}>
            {Math.min(recebidas, 99)} de {META_DE_OPCOES}{bateu ? '' : ` · faltam ${META_DE_OPCOES - recebidas}`}
          </span>
        </div>
        <div className={`mt-1 ${v3 ? 'h-1' : 'h-1.5'} rounded-full overflow-hidden`} style={{ background: 'var(--wa-divider)' }}>
          <div className="h-full rounded-full" style={{ width: `${meta}%`, background: v3 || bateu ? 'var(--wa-green)' : '#d97706' }} />
        </div>
      </div>
    </div>
  )
}

/** Os detalhes da busca ativa, cada um fechado até alguém abrir (02/11). O pedido nos grupos mora dentro de Grupos. */
function Detalhes({ a, leadId, aoEnviar }: { a: BuscaAtiva | null; leadId: string; aoEnviar: () => void }) {
  // os pedidos de cada grupo: quantas vezes foi, o último e se parou (3 pedidos sem imóvel, 29/10)
  const grupos = useMemo(() => {
    const m = new Map<string, { nome: string; vezes: number; ultimo: string; parou: boolean; teste: boolean; mao: number }>()
    for (const g of a?.grupos || []) {
      const x = m.get(g.grupo) || { nome: g.nome || g.grupo, vezes: 0, ultimo: '', parou: false, teste: !!g.teste, mao: 0 }
      if (g.encerrou) x.parou = true
      else { x.vezes += 1; x.ultimo = g.em || x.ultimo; x.parou = false; if (g.manual) x.mao += 1 }
      m.set(g.grupo, x)
    }
    return [...m.values()].sort((p, q) => (q.ultimo || '').localeCompare(p.ultimo || ''))
  }, [a?.grupos])
  const lista = 'space-y-1 text-[12px] leading-4'
  return (
    <div className="mt-3 rounded-lg px-2.5 max-h-[52vh] overflow-y-auto wa-rolagem"
         style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-panel)' }}>
      <Secao titulo="Grupos" n={grupos.length}>
        {grupos.length > 0 && (
          <ul className={lista} style={{ color: 'var(--wa-text)' }}>
            {grupos.map((g) => (
              <li key={g.nome}>
                <span className="block truncate">{g.nome}</span>
                <span className="block text-[11px]" style={{ color: 'var(--wa-text-2)' }}>
                  {g.vezes}×{g.mao ? ` (${g.mao} à mão)` : ''} · {quando(g.ultimo)}{g.parou ? ' · parou' : ''}{g.teste ? ' · teste' : ''}
                </span>
              </li>
            ))}
          </ul>
        )}
        <PedirNosGrupos leadId={leadId} aoEnviar={aoEnviar} />
      </Secao>
      {(a?.olx || []).length > 0 && (
        <Secao titulo="Anunciantes da OLX" n={a!.olx.length}>
          <ul className={lista} style={{ color: 'var(--wa-text)' }}>
            {a!.olx.map((o, n) => (
              <li key={n}>
                <b>{o.anunciante || 'Anunciante'}</b> · {o.titulo ? o.titulo.slice(0, 60) : 'anúncio'}
                <span style={{ color: 'var(--wa-text-2)' }}> · {[reais(o.preco), o.bairro, quando(o.em)].filter(Boolean).join(' · ')}</span>
              </li>
            ))}
          </ul>
        </Secao>
      )}
      {(a?.corretores || []).length > 0 && (
        <Secao titulo="Corretores que responderam" n={a!.corretores.length}>
          <ul className={lista} style={{ color: 'var(--wa-text)' }}>
            {a!.corretores.map((c, n) => (
              <li key={n}>
                <b>{c.nome || c.telefone}</b>
                <span style={{ color: 'var(--wa-text-2)' }}> · {[c.estado, c.codigo ? `#${c.codigo}` : null, c.origem, quando(c.em)].filter(Boolean).join(' · ')}</span>
              </li>
            ))}
          </ul>
        </Secao>
      )}
      {(a?.ofertas || []).length > 0 && (
        <Secao titulo="Ofertas" n={a!.ofertas.length}>
          <ul className={lista} style={{ color: 'var(--wa-text)' }}>
            {a!.ofertas.map((o, n) => (
              <li key={n}>
                {o.codigo ? <b>#{o.codigo}</b> : null} {o.nome || ''}
                <span style={{ color: 'var(--wa-text-2)' }}> · {[o.estado, quando(o.em)].filter(Boolean).join(' · ')}</span>
              </li>
            ))}
          </ul>
        </Secao>
      )}
      {(a?.passos || []).length > 0 && (
        <Secao titulo="Etapas da busca" n={a!.passos.length}>
          <ol className="space-y-1 text-[11.5px] leading-4">
            {a!.passos.map((p, n) => (
              <li key={n} className="flex gap-2">
                <span className="shrink-0 w-[74px] tabular-nums" style={{ color: 'var(--wa-text-2)' }}>{quando(p.em)}</span>
                <span style={{ color: 'var(--wa-text)' }}>
                  <b style={{ color: COR }}>{LUGAR[p.lugar] || p.lugar}</b> · {p.texto}
                </span>
              </li>
            ))}
          </ol>
        </Secao>
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
  const v3 = useModoV3()

  // 02/11 (Pedro: "ta muito texto sem categoria e com coisa que nao precisa estar aberto desde o comeco"): o topo mostra o
  // pedido, o resumo e as opções nota 90+; grupos, OLX, corretores, ofertas e etapas ficam fechados em seções com contagem.
  // O pedido nos grupos (01/11) mora dentro de Grupos, que aparece mesmo sem busca ativa.
  const nossos = (buscas || []).flatMap((b) => b.imoveis)
  if (buscas === null && !ativa) return null
  const sit = ativa ? (SITUACAO[ativa.estado] || { rotulo: ativa.estado, cor: 'var(--wa-text-2)' }) : null
  return (
    <section className="px-4 py-3.5" style={{ background: 'var(--wa-panel)' }}>
      <div className={v3 ? '' : 'rounded-xl p-3'} style={v3 ? undefined : { border: `1.5px solid ${COR}`, background: `color-mix(in srgb, ${COR} 6%, var(--wa-panel))` }}>
        <div className="flex items-center justify-between gap-2 mb-2">
          <h3 className={v3 ? 'text-[13px] font-medium flex items-center gap-1.5' : 'text-[15px] font-bold flex items-center gap-1.5'} style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>
            <MagnifyingGlass size={v3 ? 14 : 17} weight="bold" style={{ color: v3 ? 'var(--wa-text-2)' : COR }} /> Busca do lead
          </h3>
          <button type="button" onClick={() => void ler()} className="wa-icone-btn !w-7 !h-7" title="Ler de novo" aria-label="Ler de novo">
            {carregando ? <CircleNotch size={14} className="animate-spin" /> : <ArrowsClockwise size={14} />}
          </button>
        </div>
        {ativa && sit && (
          <div className="flex items-center gap-2 flex-wrap mb-2.5">
            <span className={v3 ? 'inline-flex items-center gap-1.5 text-[12px]' : 'inline-flex items-center gap-1.5 rounded-full px-2.5 py-[3px] text-[12px] font-semibold'}
                  style={v3 ? { color: 'var(--wa-text)' } : { background: `color-mix(in srgb, ${sit.cor} 14%, transparent)`, color: sit.cor }}>
              <span className={v3 ? 'w-1.5 h-1.5 rounded-full' : 'w-2 h-2 rounded-full'} style={{ background: sit.cor }} />{sit.rotulo}
            </span>
            {ativa.teste && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>em teste</span>}
            {ativa.ativada_em && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>ativada {quando(ativa.ativada_em)}</span>}
          </div>
        )}
        {ativa?.estado === 'encerrada' && ativa.motivo && (
          <p className="text-[12px] mb-2" style={{ color: 'var(--wa-tag-tel)' }}>{ativa.motivo}</p>
        )}
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
        </div>
        {(buscas?.length || ativa) ? <div className="mt-3"><ResumoDaBusca buscas={buscas || []} a={ativa} /></div> : null}
        {(buscas || []).length > 0 && <OpcoesNota90 imoveis={nossos} />}
        <Detalhes a={ativa} leadId={leadId} aoEnviar={() => void ler()} />
      </div>
    </section>
  )
}
