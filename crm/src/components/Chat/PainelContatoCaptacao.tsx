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
import AgentesDoLead from './AgentesDoLead'
import BuscasDoLead from './BuscasDoLead'
import PausaDaNay from './PausaDaNay'
import { useCallback, useEffect, useState, type ReactNode } from 'react'
import {
  X, User, House, ArrowClockwise, Copy, Check, Plus, PencilSimple, Images, CircleNotch, Robot,
} from '@phosphor-icons/react'
import EnviarImovelPelaCaptacao from './EnviarImovelPelaCaptacao'
import CardDoImovelDoDono from './CardDoImovelDoDono'
import EtiquetasDoCard from './EtiquetasDoCard'
import { useOlxClientes, recarregarOlxClientes } from '@/hooks/useOlxClientes'
import { marcarEtapaManual } from '@/hooks/useCaptacaoDonos'
import { fim8 } from '@/lib/olxClientes'
import type { LeadWithOwner } from '@/lib/types'
import { formatPhone } from '@/lib/utils'
import { corDaPontuacao } from '@/lib/pontuacaoDoCadastro'
import { numeroParaCopiar } from './PainelContatoParceria'
import EtapaDaCaptacao from './EtapaDaCaptacao'
import EtapaDoClienteOlx from './EtapaDoClienteOlx'
import AgendarVisita from './AgendarVisita'
import { CalendarPlus } from '@phosphor-icons/react'
import AgendarFollowup from './AgendarFollowup'
import CadastroDeImovel, { type AlvoDoCadastro, type FotoDaConversa } from './CadastroDeImovel'
import { usePuxador } from '@/hooks/usePuxador'
import { AVISO_DAS_24_HORAS } from './AgendarNoCardOficial'
import TagParceiro from '@/components/TagParceiro'

/** v3 (Pedro, 04/11, o painel do lead no visual novo): o que vem da tela da v3 (as mesmas peças do card e do chat) */
export interface PainelV3 {
  anel: string
  numero: ReactNode
  pilula: ReactNode
  quemResponde: ReactNode
  /** a barra das etapas da Nay (só lead); null para corretor e proprietário */
  etapa: ReactNode | null
  ehLead: boolean
}

/** v3: a seção recolhível (aberta de início), com as superfícies do sistema novo */
function SecaoV3({ titulo, children, fechada }: { titulo: string; children: React.ReactNode; fechada?: boolean }) {
  return (
    <details open={!fechada} className="group px-4 py-3" style={{ background: 'var(--wa-panel)' }}>
      <summary className="flex items-center justify-between cursor-pointer list-none select-none text-[13px] font-medium" style={{ color: 'var(--wa-text)' }}>
        {titulo}
        <span className="text-[11px] transition-transform group-open:rotate-180" style={{ color: 'var(--wa-text-2)' }}>▾</span>
      </summary>
      <div className="mt-2.5">{children}</div>
    </details>
  )
}

/** v3: um botão primário por seção (a cor de destaque) e os secundários com contorno */
const PRIMARIO_V3 = { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }
const SECUNDARIO_V3 = { color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }

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

/** 04/11: sem foto nenhuma saía "0 fotos que ele mandou..." (o "O fotos") */
const textoDasFotos = (n: number) => n
  ? `As ${n} foto${n === 1 ? '' : 's'} que ele mandou aqui entram no cadastro; você escolhe quais.`
  : 'As fotos que ele mandar aqui entram no cadastro; você escolhe quais.'

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

export default function PainelContatoCaptacao({ lead, modo, aoFechar, oficial, onTagsChange, topo, trocaDaEtapa, v3 }: {
  lead: LeadWithOwner
  modo: 'lateral' | 'gaveta'
  aoFechar: () => void
  /** aberto na aba Oficial (09/10): a conversa é pelo número da Meta, com a regra das 24 h */
  oficial?: boolean
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  /** 03/11 (Pedro): o que vem antes de tudo no card -- no Chat Captação, o contexto da captação */
  topo?: ReactNode
  /** 04/11 (Pedro): no lugar das etapas -- no Chat Captação, a lista do tipo do contato (Lead, Corretor, Proprietário) */
  trocaDaEtapa?: ReactNode
  /** v3: o painel no visual novo (ordem e estilo); as funções são as mesmas */
  v3?: PainelV3
}) {
  const [d, setD] = useState<Dados | null>(null)
  /* 20/10 (Pedro: "adicione no card do lead que abre na direita uma forma de editar o nome do contato"): o lápis ao lado
     do nome. O nome posto aqui (o apelido) vale antes do nome do dono que veio da campanha. */
  const [editandoNome, setEditandoNome] = useState(false)
  const [nomeNovo, setNomeNovo] = useState('')
  const [apelido, setApelido] = useState<string | null>(((lead as any).custom_attributes?.apelido as string) || null)
  useEffect(() => { setApelido(((lead as any).custom_attributes?.apelido as string) || null); setEditandoNome(false) }, [lead.id]) // eslint-disable-line react-hooks/exhaustive-deps
  const salvarNome = async () => {
    const novo = nomeNovo.trim()
    if (!novo) { setEditandoNome(false); return }
    const r = await fetch(`/api/leads/${lead.id}/contato`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ apelido: novo }) }).catch(() => null)
    if (r?.ok) { setApelido(novo); setEditandoNome(false) }
  }
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [alvo, setAlvo] = useState<AlvoDoCadastro | null>(null)
  const [copiado, setCopiado] = useState(false)
  // 18/10 (Pedro: "põe o card de criar visita no card lateral do contato do número de captação também")
  const [visitaAberta, setVisitaAberta] = useState(false)
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
      await Promise.all([ler(), recarregarOlxClientes(), marcarEtapaManual(lead.id, acao === 'parar' ? 'com_o_tel' : 'todos')])
    } catch (e: any) {
      setAvisoDaNay({ ok: false, texto: e?.message || 'Não consegui.' })
    } finally {
      setMexendoNaNay(null)
    }
  }

  /* 29/10 (Pedro: "como a Joelma veio da OLX perguntando de um ap e está com a tag Prop?"): o "Parar Nay" do cliente da
     OLX grava a etapa Com o Tel à mão (242), e quem só tem essa escolha entra no cadastro dos donos (captação 0), para a
     aba Tel. Cliente da Nay Leads que não está em nenhuma lista da captação não é dono: o card é o de cliente. */
  const dono = d?.dono && (d.dono.captacaoId > 0 || !olxDele) ? d.dono : null
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
      {topo}

      <div className="flex-1 overflow-y-auto wa-rolagem flex flex-col gap-2">
        {/* 1. quem é */}
        <div className="flex flex-col items-center text-center px-6 pt-5 pb-4" style={{ background: 'var(--wa-panel)' }}>
          <div className="w-[92px] h-[92px] rounded-full overflow-hidden flex items-center justify-center mb-2.5"
               style={{ backgroundColor: 'var(--wa-row-selected)' }}>
            {lead.avatar_url
              ? <img src={lead.avatar_url} alt="" className="w-full h-full object-cover" />
              : <User size={52} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.5 }} />}
          </div>
          {editandoNome ? (
            <form className="flex items-center gap-1.5 w-full max-w-[300px]" onSubmit={(e) => { e.preventDefault(); void salvarNome() }}>
              <input value={nomeNovo} onChange={(e) => setNomeNovo(e.target.value)} autoFocus maxLength={120} aria-label="Nome do contato"
                     className="flex-1 min-w-0 h-9 px-3 rounded-lg text-[16px] text-center"
                     style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
              <button type="submit" className="wa-icone-btn !w-8 !h-8" title="Salvar o nome" aria-label="Salvar o nome">
                <Check size={17} weight="bold" style={{ color: 'var(--wa-green)' }} />
              </button>
              <button type="button" className="wa-icone-btn !w-8 !h-8" onClick={() => setEditandoNome(false)} aria-label="Cancelar"><X size={16} /></button>
            </form>
          ) : (
            <p className="text-[18px] leading-6 break-words flex items-center justify-center gap-1" style={{ color: 'var(--wa-text)' }}>
              {apelido || dono?.nome || c?.nome || formatPhone(lead.title)}
              <button type="button" className="wa-icone-btn !w-7 !h-7 opacity-70 hover:opacity-100" title="Editar o nome do contato"
                      aria-label="Editar o nome do contato"
                      onClick={() => { setNomeNovo(apelido || dono?.nome || c?.nome || lead.title || ''); setEditandoNome(true) }}>
                <PencilSimple size={15} />
              </button>
            </p>
          )}
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
                    title="A Nay para de responder esta pessoa de vez (não é a pausa de 30 min de quando a equipe escreve), e o disparo e o lembrete não chamam mais. Volta só com 'Nay voltar a atender'">
              {mexendoNaNay === 'parar' ? <CircleNotch size={14} className="animate-spin" /> : <Robot size={14} weight="fill" />} Parar Nay sempre
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
          {/* 28/10 (Pedro): a equipe escreveu e a Nay Leads espera 30 min; só para quem a Nay Leads atende e não está parado */}
          {!oficial && olxDele && !naoResponde && <PausaDaNay leadId={lead.id} mexeuEm={lead.last_activity_at} />}
        </div>

        {/* a etapa (242); 18/10 (Pedro: "as Etapas da captação não estão lá no número de captação"): quem não é dono da
            campanha (cliente da OLX, orgânico) ganha a etapa do cliente da OLX, a mesma do botão direito da lista */}
        <div style={{ background: 'var(--wa-panel)' }}>
          {trocaDaEtapa ?? (dono
            ? <EtapaDaCaptacao leadId={lead.id} etapaManual={dono.etapaManual} abas={dono.abas} oficial={oficial}
                               aoMudar={(etapa) => { void ler(); void marcarEtapaManual(lead.id, etapa) }} />
            : !oficial && <EtapaDoClienteOlx telefone={lead.phone} leadId={lead.id} comOTel={!!c?.comOTel} aoMudar={() => void ler()} />)}
        </div>

        {/* 28/10 (Pedro): as buscas do lead e os nossos imóveis que servem, com a nota (nayia 510). 29/10: "em mais destaque
            no card do lead": sobe para cá, logo depois da etapa, com a busca de agora e para quem a Nay perguntou (521) */}
        {!oficial && <BuscasDoLead leadId={lead.id} />}

        {/* 24/10 (Pedro): os agentes da Nay Leads -- a legenda de cores e o histórico de cada agente que ativou, em tags */}
        {!oficial && <AgentesDoLead leadId={lead.id} />}

        {/* 17/10 (Pedro): as etiquetas da equipe também no card da Captação */}
        <Secao titulo="Etiquetas">
          <EtiquetasDoCard lead={lead as any} onTagsChange={onTagsChange} alinhar="esquerda" />
        </Secao>

        {/* 20/10 (Pedro: "quando ela for falar com um proprietário coloca um card com o imóvel do proprietário no menu à
            direita"): o card do WhatsApp de cada imóvel dele, o da campanha primeiro */}
        {(dono || c) && (imoveis.length > 0 || c?.codigo) && (
          <Secao titulo={imoveis.length > 1 ? `Imóveis do proprietário (${imoveis.length})` : 'Imóvel do proprietário'}>
            <div className="space-y-3">
              {(imoveis.length
                ? [...imoveis].sort((a, b) => Number(!!b.daCampanha) - Number(!!a.daCampanha))
                : [{ codigo: c!.codigo, daCampanha: true }]
              ).map((i: any) => <CardDoImovelDoDono key={i.codigo} codigo={Number(i.codigo)} daCampanha={!!i.daCampanha} />)}
            </div>
          </Secao>
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
            {textoDasFotos(fotos.length)}
          </p>
        </Secao>

        {/* enviar imóvel pelo 8595 (396); 17/10: também na aba Oficial (sai pelo 8595) */}
        {/* 18/10 (Pedro: "põe o card de criar visita no card lateral do contato do número de captação também"): a mesma
            ferramenta da Parceria. No card do dono, os imóveis são os dele e o lembrete sai por esta conversa; no de
            um cliente, escolhe-se o imóvel e o corretor; a visita entra na agenda, que é uma só para todos os números. */}
        <Secao titulo="Agendar visita">
          {visitaAberta ? (
            dono && imoveis.length
              ? <AgendarVisita key={lead.id} imoveis={imoveis.map((i) => String(i.codigo))} proprietarioLeadId={lead.id}
                               aoCancelar={() => setVisitaAberta(false)} aoAgendar={() => setVisitaAberta(false)} />
              : <AgendarVisita key={lead.id} aoCancelar={() => setVisitaAberta(false)} aoAgendar={() => setVisitaAberta(false)} />
          ) : (
            <button type="button" onClick={() => setVisitaAberta(true)}
                    className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold"
                    style={{ background: '#2563eb', color: '#fff' }}
                    title="Agendar uma visita à mão: corretor, imóvel, dia, duração e lembrete">
              <CalendarPlus size={14} weight="fill" /> Agendar visita
            </button>
          )}
        </Secao>

        <Secao titulo="Enviar imóvel">
          <EnviarImovelPelaCaptacao leadId={lead.id} telefone={lead.phone} oficial={oficial} />
        </Secao>

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

  /* O PAINEL NA V3 (Pedro, 04/11: "rebranding desse painel ... não remova nenhuma funcionalidade, só reorganize e
     reestilize"). A ordem: 1 topo, 2 quem está respondendo (com Parar / Voltar a Nay e o Responsável), 3 a etapa, 4 as ações
     rápidas recolhíveis, 5 a busca do lead, 6 imóveis, etiquetas e histórico; depois o que a campanha sabe, a ficha e as fotos */
  const responsavel = dono?.etapaManual === 'lucas' ? 'lucas' : naoResponde ? 'com_o_tel' : 'todos'
  const [mudandoResp, setMudandoResp] = useState(false)
  async function escolherResponsavel(etapa: string) {
    if (etapa === responsavel || mudandoResp) return
    setMudandoResp(true); setAvisoDaNay(null)
    try {
      const r = await fetch(`/api/leads/${lead.id}/captacao-etapa`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa }),
      })
      const j = await r.json().catch(() => ({} as any))
      if (!r.ok || j?.ok === false) throw new Error(j?.mensagem || j?.error || 'Não consegui.')
      setAvisoDaNay({ ok: true, texto: j?.mensagem || 'Responsável trocado.' })
      await Promise.all([ler(), recarregarOlxClientes(), marcarEtapaManual(lead.id, etapa)])
    } catch (e: any) {
      setAvisoDaNay({ ok: false, texto: e?.message || 'Não consegui.' })
    } finally { setMudandoResp(false) }
  }
  const corpoV3 = v3 && (
    <div className="flex flex-col h-full min-h-0" style={{ background: 'var(--wa-app)' }}>
      <div className="wa-topo gap-3 flex-shrink-0" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
        <button type="button" className="wa-icone-btn -ml-2" onClick={aoFechar} aria-label="Fechar os dados do contato"><X size={22} /></button>
        <h2 className="text-[16px] font-normal" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>Contato</h2>
        <button type="button" className="wa-icone-btn ml-auto" onClick={() => void ler()} title="Atualizar">
          {carregando ? <CircleNotch size={18} className="animate-spin" /> : <ArrowClockwise size={18} />}
        </button>
      </div>
      {topo}

      <div className="flex-1 overflow-y-auto wa-rolagem flex flex-col gap-px" style={{ background: 'var(--wa-divider)' }}>
        {/* 1. topo */}
        <div className="flex flex-col items-center text-center px-6 pt-5 pb-4" style={{ background: 'var(--wa-panel)' }}>
          <div className="w-[84px] h-[84px] rounded-full overflow-hidden flex items-center justify-center mb-2.5"
               style={{ backgroundColor: 'var(--wa-row-selected)', boxShadow: `0 0 0 2px ${v3.anel}` }}>
            {lead.avatar_url
              ? <img src={lead.avatar_url} alt="" className="w-full h-full object-cover" />
              : <User size={48} weight="fill" style={{ color: 'var(--wa-text-2)', opacity: 0.5 }} />}
          </div>
          {editandoNome ? (
            <form className="flex items-center gap-1.5 w-full max-w-[300px]" onSubmit={(e) => { e.preventDefault(); void salvarNome() }}>
              <input value={nomeNovo} onChange={(e) => setNomeNovo(e.target.value)} autoFocus maxLength={120} aria-label="Nome do contato"
                     className="flex-1 min-w-0 h-9 px-3 rounded-lg text-[16px] text-center"
                     style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }} />
              <button type="submit" className="wa-icone-btn !w-8 !h-8" title="Salvar o nome" aria-label="Salvar o nome">
                <Check size={17} weight="bold" style={{ color: 'var(--wa-green)' }} />
              </button>
              <button type="button" className="wa-icone-btn !w-8 !h-8" onClick={() => setEditandoNome(false)} aria-label="Cancelar"><X size={16} /></button>
            </form>
          ) : (
            <p className="text-[17px] leading-6 break-words flex items-center justify-center gap-1.5 flex-wrap" style={{ color: 'var(--wa-text)' }}>
              {apelido || dono?.nome || c?.nome || formatPhone(lead.title)}
              <button type="button" className="wa-icone-btn !w-7 !h-7 opacity-70 hover:opacity-100" title="Editar o nome do contato"
                      aria-label="Editar o nome do contato"
                      onClick={() => { setNomeNovo(apelido || dono?.nome || c?.nome || lead.title || ''); setEditandoNome(true) }}>
                <PencilSimple size={15} />
              </button>
              {v3.numero}
            </p>
          )}
          {numero && (
            <p className="text-[13.5px] mt-0.5 flex items-center justify-center gap-1" style={{ color: 'var(--wa-text-2)' }}>
              <span className="select-all">{numero}</span>
              <button type="button" onClick={() => void copiar()} className="wa-icone-btn !w-7 !h-7"
                      title={copiado ? 'Copiado!' : 'Copiar o número (sem o 55)'} aria-label="Copiar o número">
                {copiado ? <Check size={15} weight="bold" style={{ color: 'var(--wa-green)' }} /> : <Copy size={15} />}
              </button>
            </p>
          )}
        </div>

        {/* o tipo do lead, no lugar das etapas antigas (o seletor vem da v3: trocaDaEtapa) */}
        {trocaDaEtapa && <div style={{ background: 'var(--wa-panel)' }}>{trocaDaEtapa}</div>}

        {/* 2. quem está respondendo: a mesma barra do chat; Parar / Voltar a Nay e o Responsável como secundários */}
        <div className="px-4 py-3 flex flex-col gap-2" style={{ background: 'var(--wa-panel)' }}>
          <p className="text-[13px] font-medium" style={{ color: 'var(--wa-text)' }}>Quem está respondendo</p>
          {v3.quemResponde}
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" onClick={() => void pararOuVoltar('parar')} disabled={!!mexendoNaNay || naoResponde}
                    className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-[12.5px] font-medium disabled:opacity-45" style={SECUNDARIO_V3}
                    title="A Nay para de responder esta pessoa de vez (não é a pausa de 30 min de quando a equipe escreve), e o disparo e o lembrete não chamam mais. Volta só com 'Nay voltar a atender'">
              {mexendoNaNay === 'parar' ? <CircleNotch size={13} className="animate-spin" /> : <Robot size={13} weight="fill" />} Parar Nay sempre
            </button>
            <button type="button" onClick={() => void pararOuVoltar('voltar')} disabled={!!mexendoNaNay || !naoResponde}
                    className="inline-flex items-center gap-1.5 h-8 px-3 rounded-lg text-[12.5px] font-medium disabled:opacity-45" style={SECUNDARIO_V3}
                    title="A Nay volta a responder esta pessoa na próxima mensagem dela">
              {mexendoNaNay === 'voltar' ? <CircleNotch size={13} className="animate-spin" /> : <Robot size={13} weight="fill" />} Nay voltar a atender
            </button>
            {/* 04/11: Com o Tel, Lucas e Todos são de responsável, não de etapa (saíram da barra das etapas) */}
            <label className="inline-flex items-center gap-1.5 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
              Responsável
              <select value={responsavel} disabled={mudandoResp} onChange={(e) => void escolherResponsavel(e.target.value)}
                      className="h-8 px-2 rounded-lg text-[12.5px] disabled:opacity-60"
                      style={{ ...SECUNDARIO_V3, background: 'var(--wa-panel)', colorScheme: 'light dark' }}
                      title="Todos: a Nay atende. Com o Tel ou Lucas: a Nay para até voltar para Todos">
                <option value="todos">Todos (a Nay)</option>
                <option value="com_o_tel">Com o Tel</option>
                <option value="lucas">Lucas</option>
              </select>
            </label>
          </div>
          {avisoDaNay && (
            <p className="text-[12px] leading-4" style={{ color: avisoDaNay.ok ? 'var(--wa-text-2)' : 'var(--wa-tag-tel)' }}>{avisoDaNay.texto}</p>
          )}
          {!oficial && olxDele && !naoResponde && <PausaDaNay leadId={lead.id} mexeuEm={lead.last_activity_at} />}
        </div>

        {/* 3. a etapa: a barra das etapas da Nay (lead). O dono da campanha tem o funil da captação, que é outro de
            propósito; corretor não entra em funil de lead */}
        {(v3.etapa || (dono && !v3.ehLead)) && (
          <div className="py-2" style={{ background: 'var(--wa-panel)' }}>
            <p className="px-4 pt-1 text-[13px] font-medium" style={{ color: 'var(--wa-text)' }}>Etapa</p>
            {v3.etapa ?? (dono && (
              <EtapaDaCaptacao leadId={lead.id} etapaManual={dono.etapaManual} abas={dono.abas} oficial={oficial}
                               aoMudar={(etapa) => { void ler(); void marcarEtapaManual(lead.id, etapa) }} />
            ))}
          </div>
        )}

        {/* 4. ações rápidas */}
        <SecaoV3 titulo="Agendar visita">
          {visitaAberta ? (
            dono && imoveis.length
              ? <AgendarVisita key={lead.id} imoveis={imoveis.map((i) => String(i.codigo))} proprietarioLeadId={lead.id}
                               aoCancelar={() => setVisitaAberta(false)} aoAgendar={() => setVisitaAberta(false)} />
              : <AgendarVisita key={lead.id} aoCancelar={() => setVisitaAberta(false)} aoAgendar={() => setVisitaAberta(false)} />
          ) : (
            <button type="button" onClick={() => setVisitaAberta(true)} style={PRIMARIO_V3}
                    className="inline-flex items-center gap-1.5 h-9 px-4 rounded-lg text-[13px] font-medium"
                    title="Agendar uma visita à mão: corretor, imóvel, dia, duração e lembrete">
              <CalendarPlus size={14} weight="fill" /> Agendar visita
            </button>
          )}
        </SecaoV3>
        <SecaoV3 titulo="Enviar imóvel">
          <EnviarImovelPelaCaptacao leadId={lead.id} telefone={lead.phone} oficial={oficial} />
        </SecaoV3>
        <SecaoV3 titulo="Agendar follow-up">
          <div className="-mx-4 -my-3"><AgendarFollowup leadId={lead.id} /></div>
          {oficial && <p className="pt-2 text-[11px] leading-4" style={{ color: 'var(--wa-text-2)' }}>{AVISO_DAS_24_HORAS}</p>}
        </SecaoV3>
        <SecaoV3 titulo="Cadastrar imóvel">
          <button type="button" onClick={() => setAlvo({ codigo: null, titulo: 'Cadastrar imóvel novo' })} style={PRIMARIO_V3}
                  className="w-full flex items-center justify-center gap-1.5 text-[13px] font-medium h-9 rounded-lg">
            <Plus size={15} weight="bold" /> Cadastrar imóvel
          </button>
          <p className="text-[11px] mt-1.5 font-normal" style={{ color: 'var(--wa-text-2)' }}>{textoDasFotos(fotos.length)}</p>
        </SecaoV3>

        {/* 5. a busca do lead (o desenho novo fica dentro dela, no modo v3) */}
        {!oficial && <BuscasDoLead leadId={lead.id} />}

        {/* 6. imóveis, etiquetas e histórico */}
        {(dono || c) && (imoveis.length > 0 || c?.codigo) && (
          <SecaoV3 titulo={imoveis.length > 1 ? `Imóveis do proprietário (${imoveis.length})` : 'Imóvel do proprietário'}>
            <div className="space-y-3">
              {(imoveis.length
                ? [...imoveis].sort((a, b) => Number(!!b.daCampanha) - Number(!!a.daCampanha))
                : [{ codigo: c!.codigo, daCampanha: true }]
              ).map((i: any) => <CardDoImovelDoDono key={i.codigo} codigo={Number(i.codigo)} daCampanha={!!i.daCampanha} />)}
            </div>
          </SecaoV3>
        )}
        <SecaoV3 titulo={`Imóveis dele (${imoveis.length})`}>
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
                    <button type="button" onClick={() => setAlvo({ codigo: i.codigo, titulo: `Imóvel #${i.codigo}` })} style={SECUNDARIO_V3}
                            className="mt-1.5 inline-flex items-center gap-1 text-[12px] font-medium px-2.5 h-7 rounded-lg">
                      <PencilSimple size={13} /> Editar dados
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </SecaoV3>
        <SecaoV3 titulo="Etiquetas">
          <EtiquetasDoCard lead={lead as any} onTagsChange={onTagsChange} alinhar="esquerda" />
        </SecaoV3>
        {!oficial && <AgentesDoLead leadId={lead.id} />}

        {c && (
          <SecaoV3 titulo="O que a campanha sabe" fechada>
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
                  <dt className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>{k}</dt>
                  <dd className="truncate" style={{ color: 'var(--wa-text)' }} title={String(v)}>{String(v)}</dd>
                </div>
              ))}
            </dl>
            {c.perguntaPendente && (
              <p className="text-[12px] mt-2 leading-4" style={{ color: 'var(--wa-text-2)' }}>
                Esperando resposta de: “{String(c.perguntaPendente).slice(0, 180)}”
              </p>
            )}
          </SecaoV3>
        )}
        {d?.ficha && (
          <SecaoV3 titulo={`Ficha da conversa${d.ficha.tipo === 'novo' ? ' (imóvel novo)' : d.ficha.codigo ? ` (#${d.ficha.codigo})` : ''}`} fechada>
            <p className="text-[12.5px] leading-4" style={{ color: 'var(--wa-text)' }}>{resumoDaFicha(d.ficha.dados) || 'ainda vazia'}</p>
            <p className="text-[11px] mt-1" style={{ color: 'var(--wa-text-2)' }}>O que ele contou nesta conversa; entra no cadastro onde o campo está vazio.</p>
          </SecaoV3>
        )}
        {!!fotos.length && (
          <SecaoV3 titulo={`Fotos que ele mandou (${fotos.length})`} fechada>
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
          </SecaoV3>
        )}
        {erro && <p className="px-4 py-3 text-[12.5px]" style={{ color: 'var(--wa-tag-tel)', background: 'var(--wa-panel)' }}>{erro}</p>}
        <div className="flex-1 min-h-4" style={{ background: 'var(--wa-app)' }} />
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

  const conteudo = v3 ? corpoV3 : corpo

  if (modo === 'gaveta') {
    return (
      <div className="fixed inset-0 z-50 flex justify-end" onClick={aoFechar}>
        <div className="absolute inset-0 bg-black/40" />
        <aside className="relative h-full w-[min(420px,92vw)] shadow-2xl" onClick={(e) => e.stopPropagation()}>{conteudo}</aside>
      </div>
    )
  }
  return (
    <aside className="relative h-full flex-shrink-0" style={{ width: borda.largura, borderLeft: '1px solid var(--wa-divider)' }}>
      <div {...borda.puxador} />
      {conteudo}
    </aside>
  )
}
