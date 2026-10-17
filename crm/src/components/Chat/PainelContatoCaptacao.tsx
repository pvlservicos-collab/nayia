'use client'

/**
 * O CARD DO CORRETOR NA CAPTAÇÃO (Pedro, 01/10/2026):
 *
 *   "quero reformular totalmente o card de proprietário lá do WhatsApp de
 *    captação, quero informações úteis lá no card, já aparecendo o imóvel dele,
 *    e uma opção de editar o imóvel dele para atualizar as informações por lá, e
 *    uma opção de cadastrar um imóvel novo... adicione a mesma ferramenta de
 *    mudar a etapa do lead que nem na parceria mas com as etapas da captação, e
 *    adicione lá mais uma etapa, followup, e adicione embaixo no card essa
 *    função de agendar msg."
 *
 * Antes a captação usava o card genérico do CRM (pedido, venda, agenda do quiz)
 * com uma caixinha do proprietário no fim. Agora o card é só o que é desta
 * linha: na captação nós falamos com quem TEM imóvel.
 *
 *   1. quem é, e a etapa da captação (242, com Follow-up)
 *   2. o que a campanha sabe: situação do imóvel, valor pedido, se quer vender,
 *      quando respondeu, a pergunta que ficou pendente
 *   3. os imóveis dele, cada um com quanto o cadastro está preenchido (244) e
 *      "Editar dados"
 *   4. "Cadastrar imóvel" -- o popup de CadastroDeImovel
 *   5. agendar follow-up (a mesma caixa da Parceria)
 *   6. a ficha que a conversa abriu e as fotos que ele mandou
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import {
  X, User, House, ArrowClockwise, Copy, Check, Plus, PencilSimple, Images, CircleNotch, Robot,
  PaperPlaneRight, CheckCircle, WarningCircle,
} from '@phosphor-icons/react'
import EscolherImoveis, { useOpcoesDoDisparo, type ImovelParaEnviar } from '@/components/Disparo/EscolherImoveis'
import { useOlxClientes, recarregarOlxClientes } from '@/hooks/useOlxClientes'
import { fim8 } from '@/lib/olxClientes'
import type { LeadWithOwner } from '@/lib/types'
import { formatPhone } from '@/lib/utils'
import { corDaPontuacao } from '@/lib/pontuacaoDoCadastro'
import { numeroParaCopiar } from './PainelContatoParceria'
import EtapaDaCaptacao from './EtapaDaCaptacao'
import AgendarFollowup from './AgendarFollowup'
import CadastroDeImovel, { type AlvoDoCadastro, type FotoDaConversa } from './CadastroDeImovel'
import { usePuxador } from '@/hooks/usePuxador'
import { AVISO_DAS_24_HORAS } from './AgendarNoCardOficial'
import TagParceiro from '@/components/TagParceiro'

interface ImovelDoCard {
  codigo: number; condominio: string | null; tipo: string | null; bairro: string | null; status: string | null
  disponivel: boolean | null; parceiro: boolean; aluguel: number | null; venda: number | null
  capa: string | null; fotos: number; daCampanha: boolean
}
interface Dados {
  dono: { nome: string | null; condominio: string | null; codigo: string | null; bairro: string | null; tipo: string | null; captacaoId: number; abas: string[]; etapaManual: string | null } | null
  campanha: Record<string, any> | null
  imoveis: ImovelDoCard[]
  ficha: { id: number; tipo: string; codigo: number | null; estado: string; dados: Record<string, any>; fotos: number } | null
  fotos: FotoDaConversa[]
  pontuacao: Record<string, { pct: number; falta: string[]; faltaEssencial: string[] }>
  condominiosCitados: Array<{ id: number; nome: string; bairro: string | null }>
}

const reais = (v: number | null | undefined) =>
  v == null || Number(v) <= 0 ? null : Number(v).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })

const dia = (v: string | null | undefined) => {
  if (!v) return null
  const d = new Date(v)
  return Number.isNaN(d.getTime()) ? null : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

const SITUACAO: Record<string, string> = {
  disponivel: 'disponível', alugado: 'alugado', vendido: 'vendido', indisponivel: 'indisponível',
}

const ROTULO_DA_FICHA: Record<string, string> = {
  tipo: 'tipo', bairro: 'bairro', condominio: 'condomínio', quartos: 'quartos', suites: 'suítes',
  banheiros: 'banheiros', vagas: 'vagas', area: 'área', valor: 'valor', negocio: 'negócio',
  mobilia: 'mobília', condominio_valor: 'taxa', iptu: 'IPTU', incluso: 'incluso', detalhes: 'detalhes',
}

function resumoDaFicha(dados: Record<string, any> | undefined): string {
  if (!dados) return ''
  return Object.entries(dados)
    .filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '')
    .slice(0, 8)
    .map(([k, v]) => `${ROTULO_DA_FICHA[k] || k}: ${String(v).slice(0, 40)}`)
    .join(' · ')
}

function Secao({ titulo, children, acao }: { titulo: string; children: React.ReactNode; acao?: React.ReactNode }) {
  return (
    <section className="px-4 py-3.5" style={{ background: 'var(--wa-panel)' }}>
      <div className="flex items-center justify-between gap-2 mb-2">
        <h3 className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{titulo}</h3>
        {acao}
      </div>
      {children}
    </section>
  )
}

/** A barra de quanto o cadastro está preenchido -- a mesma régua da aba Imóveis. */
function Barra({ pct, falta }: { pct: number; falta: string[] }) {
  return (
    <div className="mt-1" title={falta.length ? `Falta: ${falta.join(', ')}` : 'Cadastro completo'}>
      <div className="flex items-center gap-1.5">
        <div className="flex-1 h-1.5 rounded-full overflow-hidden" style={{ background: 'var(--wa-row-selected)' }}>
          <div className="h-full rounded-full" style={{ width: `${pct}%`, background: corDaPontuacao(pct) }} />
        </div>
        <b className="text-[11px] tabular-nums" style={{ color: corDaPontuacao(pct) }}>{pct}%</b>
      </div>
      {!!falta.length && (
        <p className="text-[11px] mt-0.5 truncate" style={{ color: 'var(--wa-text-2)' }}>
          falta {falta.slice(0, 3).join(', ')}{falta.length > 3 ? ` +${falta.length - 3}` : ''}
        </p>
      )}
    </div>
  )
}

export default function PainelContatoCaptacao({ lead, modo, aoFechar, oficial }: {
  lead: LeadWithOwner
  modo: 'lateral' | 'gaveta'
  aoFechar: () => void
  /** aberto na aba Oficial (09/10): a conversa é pelo número da Meta, com a regra das 24 h */
  oficial?: boolean
}) {
  const [d, setD] = useState<Dados | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [alvo, setAlvo] = useState<AlvoDoCadastro | null>(null)
  const [copiado, setCopiado] = useState(false)
  /* a borda esquerda puxa para alargar (Pedro, 09/10), como no card da Parceria */
  const borda = usePuxador('crm:largura-card-captacao', { min: 300, max: 640, padrao: 380, lado: 'esquerda' })

  const ler = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/captacao/dono/${lead.id}`)
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      setD(j); setErro(null)
    } catch (e: any) {
      setErro(e?.message || 'Não consegui ler este contato.')
    } finally {
      setCarregando(false)
    }
  }, [lead.id])

  useEffect(() => { void ler() }, [ler])

  const numero = numeroParaCopiar(lead.phone)
  async function copiar() {
    if (!numero) return
    try { await navigator.clipboard.writeText(numero); setCopiado(true); setTimeout(() => setCopiado(false), 1500) } catch { /* sem área de transferência */ }
  }

  /* ── ENVIAR IMÓVEL pelo número de captação (Pedro, 16/10: "coloca esse campo nos cards dos leads também do de
     captação"). A mesma escolha da Parceria (um a um ou por faixa); quem manda é a Nay do WhatsApp (nay-olx), card +
     fotos, um imóvel por vez, pelo 8595 (migração 396). O card acompanha o pedido até terminar. ── */
  const { opcoes: opcoesDoDisparo, teto: tetoDoDisparo } = useOpcoesDoDisparo()
  const [escolhidos, setEscolhidos] = useState<ImovelParaEnviar[]>([])
  const [rodadaDoEnvio, setRodadaDoEnvio] = useState(0)
  const [enviando, setEnviando] = useState(false)
  const [envio, setEnvio] = useState<{ tipo: 'ok' | 'erro' | 'aviso' | 'vai'; texto: string } | null>(null)
  const vigiaDoEnvio = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => { if (vigiaDoEnvio.current) clearTimeout(vigiaDoEnvio.current) }, [])
  useEffect(() => { setEscolhidos([]); setEnvio(null) }, [lead.id])
  const acompanharEnvio = useCallback((id: number, desde: number) => {
    vigiaDoEnvio.current = setTimeout(async () => {
      try {
        const r = await fetch(`/api/captacao/enviar-imoveis?id=${id}`)
        const e = await r.json().catch(() => ({}))
        if (e?.estado === 'enviado' || e?.estado === 'falhou') {
          setEnviando(false)
          setEnvio({ tipo: e.estado === 'enviado' ? 'ok' : 'erro', texto: e.resultado || (e.estado === 'enviado' ? 'Enviado.' : 'Não saiu.') })
          return
        }
        const feitos = Array.isArray(e?.enviados) ? e.enviados.length : 0
        const total = Array.isArray(e?.codigos) ? e.codigos.length : 0
        setEnvio({ tipo: 'vai', texto: `Enviando pelo 8595… ${feitos} de ${total}` })
      } catch { /* sem rede: tenta de novo */ }
      if (Date.now() - desde < 15 * 60_000) acompanharEnvio(id, desde)
      else { setEnviando(false); setEnvio({ tipo: 'aviso', texto: 'O envio está demorando; ele continua saindo pela Nay.' }) }
    }, 3000)
  }, [])
  async function enviarImoveis() {
    if (!escolhidos.length || enviando) return
    setEnviando(true)
    setEnvio({ tipo: 'vai', texto: 'Pedindo o envio…' })
    try {
      const r = await fetch('/api/captacao/enviar-imoveis', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone: lead.phone, codigos: escolhidos.map((e) => Number(e.codigo)) }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j?.id) throw new Error(j?.error || 'não consegui pedir o envio')
      setEscolhidos([])
      setRodadaDoEnvio((n) => n + 1)
      setEnvio({ tipo: 'vai', texto: 'Na fila da Nay: sai em alguns segundos, um imóvel de cada vez.' })
      acompanharEnvio(Number(j.id), Date.now())
    } catch (e: any) {
      setEnviando(false)
      setEnvio({ tipo: 'erro', texto: e?.message || 'não consegui pedir o envio' })
    }
  }

  /* 398 (Pedro, 16/10: "não consigo parar a Nay"): o cliente da OLX e o orgânico são da Nay do WhatsApp; o botão
     também a para, e o card mostra o estado dela (antes só via o da campanha) */
  const olxDele = useOlxClientes(!oficial)[fim8(lead.phone)]
  const [mexendoNaNay, setMexendoNaNay] = useState<'parar' | 'voltar' | null>(null)
  const [avisoDaNay, setAvisoDaNay] = useState<{ ok: boolean; texto: string } | null>(null)
  useEffect(() => { setAvisoDaNay(null) }, [lead.id])
  async function pararOuVoltar(acao: 'parar' | 'voltar') {
    if (mexendoNaNay) return
    setMexendoNaNay(acao); setAvisoDaNay(null)
    try {
      const r = await fetch(`/api/leads/${lead.id}/captacao-etapa`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ etapa: acao === 'parar' ? 'com_o_tel' : 'todos' }),
      })
      const j = await r.json().catch(() => ({} as any))
      if (!r.ok || j?.ok === false) throw new Error(j?.mensagem || j?.error || 'Não consegui.')
      setAvisoDaNay({ ok: true, texto: acao === 'parar'
        ? 'Nay parada para esta pessoa. A conversa foi para a etapa Com o Tel.'
        : 'A Nay voltou a atender esta pessoa: responde na próxima mensagem dela.' })
      await Promise.all([ler(), recarregarOlxClientes()])
    } catch (e: any) {
      setAvisoDaNay({ ok: false, texto: e?.message || 'Não consegui.' })
    } finally {
      setMexendoNaNay(null)
    }
  }

  const dono = d?.dono || null
  const c = d?.campanha || null
  // a Nay da campanha parada (Com o Tel) ou a Nay do WhatsApp fora da conversa (398)
  const naoResponde = !!c?.comOTel || !!olxDele?.humano
  const imoveis = d?.imoveis || []
  const fotos = d?.fotos || []

  const corpo = (
    <div className="flex flex-col h-full min-h-0" style={{ background: 'var(--wa-app)' }}>
      <div className="wa-topo gap-3 flex-shrink-0" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
        <button type="button" className="wa-icone-btn -ml-2" onClick={aoFechar} aria-label="Fechar os dados do contato"><X size={22} /></button>
        <h2 className="text-[16px] font-normal" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>Captação</h2>
        <button type="button" className="wa-icone-btn ml-auto" onClick={() => void ler()} title="Atualizar">
          {carregando ? <CircleNotch size={18} className="animate-spin" /> : <ArrowClockwise size={18} />}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto wa-rolagem flex flex-col gap-2">
        {/* 1. quem é */}
        <div className="flex flex-col items-center text-center px-6 pt-5 pb-4" style={{ background: 'var(--wa-panel)' }}>
          <div className="w-[92px] h-[92px] rounded-full overflow-hidden flex items-center justify-center mb-2.5"
               style={{ backgroundColor: 'var(--wa-row-selected)' }}>
            {lead.avatar_url
              ? <img src={lead.avatar_url} alt="" className="w-full h-full object-cover" />
              : <User size={52} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.5 }} />}
          </div>
          <p className="text-[18px] leading-6 break-words" style={{ color: 'var(--wa-text)' }}>
            {dono?.nome || c?.nome || formatPhone(lead.title)}
          </p>
          {numero && (
            <p className="text-[14px] mt-0.5 flex items-center justify-center gap-1" style={{ color: 'var(--wa-text-2)' }}>
              <span className="select-all">{numero}</span>
              <button type="button" onClick={() => void copiar()} className="wa-icone-btn !w-7 !h-7"
                      title={copiado ? 'Copiado!' : 'Copiar o número (sem o 55)'} aria-label="Copiar o número">
                {copiado ? <Check size={15} weight="bold" style={{ color: 'var(--wa-green)' }} /> : <Copy size={15} />}
              </button>
            </p>
          )}
          {naoResponde && (
            <p className="text-[12px] mt-1" style={{ color: 'var(--wa-tag-tel)' }}>
              A Nay não responde esta pessoa{c?.comOTelMotivo ? ` — ${c.comOTelMotivo}` : ''}.
            </p>
          )}

          {/* PARAR A NAY PARA ESTE CONTATO (Pedro, 02/10/2026: "quero um botão manual de
              pausar a Nay de captação no contato"). É o atalho de um clique para a
              etapa "Com o Tel" (242), que já cala a Nay para a pessoa; "voltar a
              atender" é o "Todos", que solta. O mesmo par de botões da Parceria. */}
          <div className="flex flex-wrap justify-center gap-2 mt-3">
            <button type="button" onClick={() => void pararOuVoltar('parar')} disabled={!!mexendoNaNay || naoResponde}
                    className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
                    style={naoResponde
                      ? { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' }
                      : { color: 'var(--wa-tag-tel)', border: '1px solid color-mix(in srgb, var(--wa-tag-tel) 50%, transparent)' }}
                    title="A Nay de captação para de responder esta pessoa, e o disparo e o lembrete não chamam mais">
              {mexendoNaNay === 'parar' ? <CircleNotch size={14} className="animate-spin" /> : <Robot size={14} weight="fill" />} Parar Nay
            </button>
            <button type="button" onClick={() => void pararOuVoltar('voltar')} disabled={!!mexendoNaNay || !naoResponde}
                    className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
                    style={naoResponde
                      ? { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }
                      : { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' }}
                    title="A Nay volta a responder esta pessoa na próxima mensagem dela">
              {mexendoNaNay === 'voltar' ? <CircleNotch size={14} className="animate-spin" /> : <Robot size={14} weight="fill" />} Nay voltar a atender
            </button>
          </div>
          {avisoDaNay && (
            <p className="text-[12px] mt-2 leading-4" style={{ color: avisoDaNay.ok ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>{avisoDaNay.texto}</p>
          )}
        </div>

        {/* a etapa (242) */}
        {dono && (
          <div style={{ background: 'var(--wa-panel)' }}>
            <EtapaDaCaptacao leadId={lead.id} etapaManual={dono.etapaManual} abas={dono.abas} aoMudar={() => void ler()} />
          </div>
        )}

        {/* 2. o que a campanha sabe */}
        {c && (
          <Secao titulo="O que a campanha sabe">
            <dl className="grid grid-cols-2 gap-x-3 gap-y-1.5 text-[12.5px]">
              {[
                ['Imóvel dele', [c.tipo, c.condominio || c.bairro].filter(Boolean).join(' · ') || c.imovelDesc || null],
                ['Situação', c.situacao ? SITUACAO[c.situacao] || c.situacao : null],
                ['Aluguel pedido', reais(c.valorLocacao)],
                ['Venda pedida', reais(c.valorVenda)],
                ['Quer vender', c.querVender ? 'sim' : null],
                ['Tem outro imóvel', c.temOutroImovel ? 'sim' : null],
                ['Respondeu', dia(c.respondeuEm)],
                ['Último disparo', dia(c.ultimoEnvioEm)],
                ['Contrato até', c.contratoAte ? dia(c.contratoAte) : null],
                ['Saiu da campanha', c.optOut ? 'sim' : null],
              ].filter(([, v]) => v).map(([k, v]) => (
                <div key={String(k)} className="min-w-0">
                  <dt className="text-[11px] uppercase tracking-wide" style={{ color: 'var(--wa-text-2)' }}>{k}</dt>
                  <dd className="truncate" style={{ color: 'var(--wa-text)' }} title={String(v)}>{String(v)}</dd>
                </div>
              ))}
            </dl>
            {c.perguntaPendente && (
              <p className="text-[12px] mt-2 leading-4" style={{ color: 'var(--wa-text-2)' }}>
                <span style={{ color: 'var(--wa-text)' }}>Esperando resposta de: </span>“{String(c.perguntaPendente).slice(0, 180)}”
              </p>
            )}
          </Secao>
        )}

        {/* 3. os imóveis dele */}
        <Secao titulo={`Imóveis dele (${imoveis.length})`}>
          {!imoveis.length && (
            <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
              Nenhum imóvel dele no catálogo{c?.codigo ? ` (a campanha fala do #${c.codigo})` : ''}.
            </p>
          )}
          <div className="space-y-2.5">
            {imoveis.map((i) => {
              const p = d?.pontuacao?.[String(i.codigo)]
              return (
                <div key={i.codigo} className="flex gap-2 items-start">
                  <div className="w-12 h-12 rounded-lg overflow-hidden flex-shrink-0 flex items-center justify-center" style={{ background: 'var(--wa-row-selected)' }}>
                    {i.capa ? <img src={i.capa} alt="" className="w-full h-full object-cover" loading="lazy" />
                            : <House size={20} style={{ color: 'var(--wa-text-2)' }} />}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-[13px] truncate" style={{ color: 'var(--wa-text)' }} title={i.condominio || i.tipo || ''}>
                      {i.condominio || i.tipo || `Imóvel ${i.codigo}`}
                    </p>
                    <p className="text-[11.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>
                      #{i.codigo}{i.status ? ` · ${i.status}` : ''}{reais(i.aluguel) ? ` · ${reais(i.aluguel)}` : reais(i.venda) ? ` · ${reais(i.venda)} venda` : ''} · {i.fotos} foto{i.fotos === 1 ? '' : 's'}
                      {i.parceiro ? <> <TagParceiro /></> : null}{i.daCampanha ? ' · da campanha' : ''}
                    </p>
                    {p && <Barra pct={p.pct} falta={p.falta} />}
                    <div className="flex items-center gap-1.5 mt-1.5">
                      <button type="button" onClick={() => setAlvo({ codigo: i.codigo, titulo: `Imóvel #${i.codigo}` })}
                              className="inline-flex items-center gap-1 text-[12px] font-semibold px-2.5 py-1 rounded-full"
                              style={{ color: 'var(--wa-green)', border: '1px solid color-mix(in srgb, var(--wa-green) 50%, transparent)' }}>
                        <PencilSimple size={13} /> Editar dados
                      </button>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
          <button type="button" onClick={() => setAlvo({ codigo: null, titulo: 'Cadastrar imóvel novo' })}
                  className="w-full mt-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold py-2 rounded-lg"
                  style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
            <Plus size={15} weight="bold" /> Cadastrar imóvel
          </button>
          <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
            {fotos.length} foto{fotos.length === 1 ? '' : 's'} que ele mandou aqui entram no cadastro, você escolhe quais.
          </p>
        </Secao>

        {/* enviar imóvel pelo 8595 (396); na aba Oficial a conversa é pelo número da Meta, então não */}
        {!oficial && (
          <Secao titulo="Enviar imóvel">
            <EscolherImoveis key={rodadaDoEnvio} compacto escolhidos={escolhidos}
                             aoMudar={(l) => { setEscolhidos(l); if (!enviando) setEnvio(null) }}
                             teto={tetoDoDisparo} opcoes={opcoesDoDisparo}
                             aoAvisar={(texto) => setEnvio(texto ? { tipo: 'aviso', texto } : null)} />
            <button type="button" onClick={() => void enviarImoveis()} disabled={!escolhidos.length || enviando}
                    className="mt-3 w-full h-10 rounded-full text-[14px] font-semibold flex items-center justify-center gap-1.5 disabled:opacity-40"
                    style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
              {enviando ? <CircleNotch size={16} className="animate-spin" /> : <PaperPlaneRight size={16} weight="fill" />}
              {escolhidos.length ? `Enviar ${escolhidos.length} imóve${escolhidos.length === 1 ? 'l' : 'is'}` : 'Enviar'}
            </button>
            {envio && (
              <p className="text-[13px] mt-2 flex items-start gap-1.5 whitespace-pre-wrap"
                 style={{ color: envio.tipo === 'ok' ? 'var(--wa-green)' : envio.tipo === 'erro' ? 'var(--wa-tag-tel)'
                          : envio.tipo === 'aviso' ? 'var(--wa-tag-prop)' : 'var(--wa-text-2)' }}>
                {envio.tipo === 'vai' ? <CircleNotch size={16} className="mt-px flex-shrink-0 animate-spin" />
                  : envio.tipo === 'ok' ? <CheckCircle size={16} className="mt-px flex-shrink-0" />
                  : <WarningCircle size={16} className="mt-px flex-shrink-0" />}
                {envio.texto}
              </p>
            )}
            <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
              Sai pelo número de captação (8595-6408), card e fotos, um imóvel de cada vez. Parceria e fora do ar não saem.
            </p>
          </Secao>
        )}

        {/* 4. agendar follow-up */}
        <div style={{ background: 'var(--wa-panel)' }}>
          <AgendarFollowup leadId={lead.id} />
          {oficial && <p className="px-4 pb-2 text-[11px] leading-4" style={{ color: 'var(--wa-text-2)' }}>{AVISO_DAS_24_HORAS}</p>}
        </div>

        {/* 5. a ficha da conversa e as fotos */}
        {d?.ficha && (
          <Secao titulo={`Ficha da conversa${d.ficha.tipo === 'novo' ? ' (imóvel novo)' : d.ficha.codigo ? ` (#${d.ficha.codigo})` : ''}`}>
            <p className="text-[12.5px] leading-4" style={{ color: 'var(--wa-text)' }}>
              {resumoDaFicha(d.ficha.dados) || 'ainda vazia'}
            </p>
            <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>
              O que ele contou nesta conversa; entra no cadastro onde o campo está vazio.
            </p>
          </Secao>
        )}

        {!!fotos.length && (
          <Secao titulo={`Fotos que ele mandou (${fotos.length})`}>
            <div className="grid grid-cols-4 gap-1.5">
              {fotos.slice(0, 12).map((f) => (
                <a key={f.id} href={f.url} target="_blank" rel="noreferrer" className="aspect-square rounded-lg overflow-hidden">
                  <img src={f.url} alt="" className="w-full h-full object-cover" loading="lazy" />
                </a>
              ))}
            </div>
            <p className="text-[11px] mt-1.5 flex items-center gap-1" style={{ color: 'var(--wa-text-2)' }}>
              <Images size={13} /> no cadastro elas já vêm marcadas; você desmarca o que não serve.
            </p>
          </Secao>
        )}

        {erro && (
          <p className="px-4 py-3 text-[12.5px]" style={{ color: 'var(--wa-tag-tel)' }}>{erro}</p>
        )}
        {!dono && !carregando && !erro && (
          <p className="px-4 py-3 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
            Esta conversa não está na campanha da captação, então não há imóvel nem etapa para mostrar.
            Dá para agendar follow-up e conversar normalmente.
          </p>
        )}
        <div className="h-4 flex-shrink-0" />
      </div>

      {alvo && (
        <CadastroDeImovel
          leadId={lead.id}
          donoNome={dono?.nome || c?.nome || null}
          temProprietario={!!c?.temProprietario}
          alvo={alvo}
          fotos={fotos}
          condominiosCitados={d?.condominiosCitados || []}
          aoFechar={() => setAlvo(null)}
          aoPronto={() => void ler()}
        />
      )}
    </div>
  )

  if (modo === 'gaveta') {
    return (
      <div className="fixed inset-0 z-50 flex justify-end" onClick={aoFechar}>
        <div className="absolute inset-0 bg-black/40" />
        <aside className="relative h-full w-[min(420px,92vw)] shadow-2xl" onClick={(e) => e.stopPropagation()}>{corpo}</aside>
      </div>
    )
  }
  return (
    <aside className="relative h-full flex-shrink-0" style={{ width: borda.largura, borderLeft: '1px solid var(--wa-divider)' }}>
      <div {...borda.puxador} />
      {corpo}
    </aside>
  )
}
