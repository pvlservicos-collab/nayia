'use client'

/**
 * CHAT CAPTAÇÃO (Pedro, 03/11/2026): "cria um item no menu, Captação, lá tu coloca todos os chats que estão em cadastro
 * incompleto"; e a conversa aberta pela tela Imóveis captar OLX ("deve abrir uma conversa pelo número Parceria e essa
 * conversa ficar no proprietário Parceria e na aba Captação, já que é uma conversa de captação").
 *
 * Quem entra: /api/captacao/conversas (os donos dos Cadastros incompletos, na linha por onde falavam) e as conversas
 * marcadas (custom_attributes.conversa_captacao). A tela é a ChatJuntado (a cara do Leads, com a lupa); cada conversa
 * responde pelo número dela.
 *
 * 03/11, noite (Pedro: "no contato tinha que ter um botão de cadastrar imóvel, e no card um contexto, ex.: estávamos
 * cadastrando esse imóvel dia X e ele parou de responder, e também um botão de mandar de volta para os proprietários após
 * finalizar o cadastro"):
 *   - Cadastrar imóvel: a barra do WhatsApp Leads (CadastroImovelOlx, 535), já com o link quando veio da OLX;
 *   - o contexto no alto do card: o cadastro (o que já tinha, o que faltou, quando parou) ou o anúncio da OLX;
 *   - Mandar de volta para Proprietários: o tipo Proprietário (na Parceria, também a etapa Proprietários) e a marca de
 *     captação em FALSE -- sai daqui e da etiqueta verde, mesmo sendo cadastro incompleto (volta se o cadastro andar de novo).
 *
 * 04/11 (Pedro: "lá na captação quero um botão Mandar de volta para Corretor, e também poder mudar o status do lead que eu
 * tô falando entre corretor, proprietário ou lead: no lugar das etapas do lado do card dele, uma lista suspensa"):
 *   - Mandar de volta para Corretor: o tipo Corretor e a marca de captação em FALSE (na Parceria, a etapa Todos);
 *   - no card, no lugar das etapas, o tipo do contato (Lead = cliente, Corretor, Proprietário), gravado à mão (organizar).
 */
import { useCallback, useState, type ReactNode } from 'react'
import { tipoEscolhido } from '@/lib/organizacaoDoLead'
import { ArrowUUpLeft, ArrowSquareOut, CircleNotch } from '@phosphor-icons/react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useConversasDeCaptacao, useContextoDaCaptacao, ehDeCaptacao, recarregarCaptacao, type ContextoDaCaptacao } from '@/hooks/useConversasDeCaptacao'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import ChatJuntado from './ChatJuntado'
import { organizar } from './OrganizarConversa'

const dia = (iso?: string | null) => (iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' }) : '')
const CAMPOS: [string, string][] = [['tipo', 'tipo'], ['negocio', 'negócio'], ['bairro', 'bairro'], ['condominio', 'condomínio'],
  ['quartos', 'quartos'], ['suites', 'suítes'], ['vagas', 'vagas'], ['area', 'área'], ['valor', 'valor'], ['iptu', 'IPTU']]

/** "um apartamento no Parque 10", "o imóvel #1234": o que estávamos cadastrando */
function oQue(c: Extract<ContextoDaCaptacao, { fonte: 'cadastro' }>): string {
  if (c.tipo === 'atualizar' && c.codigo) return `a atualização do imóvel #${c.codigo}`
  const tipo = String(c.dados?.tipo || '').toLowerCase()
  const onde = c.dados?.condominio || c.dados?.bairro
  return `${tipo ? (/casa|kit/.test(tipo) ? 'uma ' : 'um ') + tipo : 'o imóvel dele'}${onde ? ` no ${onde}` : ''}`
}

const TIPOS_DO_CONTATO: [string, string][] = [['cliente', 'Lead'], ['corretor', 'Corretor'], ['proprietario', 'Proprietário']]

/** No card, no lugar das etapas: o tipo do contato, escolhido à mão */
function TipoDoContato({ lead, aoMudar }: { lead: LeadWithOwner; aoMudar: (custom: Record<string, any>) => void }) {
  const [ocupado, setOcupado] = useState(false)
  const atual = tipoEscolhido(lead) || ''
  return (
    <label className="flex items-center gap-2 px-4 py-3 text-[13px]" style={{ color: 'var(--wa-text)', borderTop: '1px solid var(--wa-divider)' }}>
      <span className="font-semibold uppercase text-[11px] tracking-wide" style={{ color: 'var(--wa-text-2)' }}>Tipo do contato</span>
      <select value={TIPOS_DO_CONTATO.some(([k]) => k === atual) ? atual : ''} disabled={ocupado}
              onChange={async (e) => {
                const tipo = e.target.value || null
                setOcupado(true)
                try { const o = await organizar(lead.id, { tipo }); aoMudar(o.custom_attributes) }
                catch (er: any) { window.alert(er?.message || 'Não consegui mudar o tipo.') } finally { setOcupado(false) }
              }}
              className="ml-auto h-8 px-2 rounded-lg text-[13px] font-semibold disabled:opacity-60"
              style={{ background: 'var(--wa-search)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>
        <option value="">Escolher…</option>
        {TIPOS_DO_CONTATO.map(([k, r]) => <option key={k} value={k}>{r}</option>)}
      </select>
    </label>
  )
}

function Contexto({ c, ocupado, aoDevolver, aoDevolverCorretor }: { c: ContextoDaCaptacao | undefined; ocupado: boolean; aoDevolver: () => void; aoDevolverCorretor: () => void }) {
  let texto: ReactNode = 'Conversa de captação.'
  let detalhes: ReactNode = null
  if (c?.fonte === 'cadastro') {
    const tem = CAMPOS.filter(([k]) => c.dados?.[k]).map(([k, r]) => `${r} ${String(c.dados[k]).slice(0, 30)}`)
    texto = <>Estávamos cadastrando <b>{oQue(c)}</b> desde {dia(c.criado_em)} e ele parou de responder em <b>{dia(c.atualizado_em)}</b>.</>
    detalhes = (
      <>
        {tem.length > 0 && <div>Já temos: {tem.join(', ')}{c.fotos ? `, ${c.fotos} foto(s)` : ''}.</div>}
        {c.faltou?.length > 0 && <div>Falta: {c.faltou.join(', ')}.</div>}
        {c.humano && <div>A equipe assumiu esta conversa (a Nay não retoma).</div>}
        {c.opt_out && <div style={{ color: '#dc2626' }}>Pediu para não receber mais mensagem.</div>}
      </>
    )
  } else if (c?.fonte === 'olx') {
    texto = <>Chamamos este dono {c.chamado_em ? `em ${dia(c.chamado_em)} ` : ''}pelo anúncio da OLX <b>{c.titulo || ''}</b>
      {[c.preco_texto, c.bairro].filter(Boolean).length ? ` (${[c.preco_texto, c.bairro].filter(Boolean).join(' · ')})` : ''}.</>
    detalhes = c.url ? (
      <a href={c.url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 underline" style={{ color: 'var(--wa-green)' }}>
        <ArrowSquareOut size={13} /> Ver o anúncio
      </a>
    ) : null
  }
  return (
    <div className="mx-3 mt-3 rounded-lg p-3 text-[13px] leading-snug flex flex-col gap-1.5 flex-shrink-0"
         style={{ background: 'color-mix(in srgb, #14532d 10%, transparent)', border: '1px solid color-mix(in srgb, #14532d 35%, transparent)', color: 'var(--wa-text)' }}>
      <span className="text-[11px] font-semibold uppercase tracking-wide" style={{ color: '#15803d' }}>Contexto da captação</span>
      <div>{texto}</div>
      {detalhes && <div className="text-[12.5px] flex flex-col gap-0.5" style={{ color: 'var(--wa-text-2)' }}>{detalhes}</div>}
      <button type="button" onClick={aoDevolver} disabled={ocupado}
              title="Depois de finalizar o cadastro: a conversa sai da Captação e volta para Proprietários no número dela"
              className="self-start mt-1 flex items-center gap-1.5 h-8 px-3 rounded-lg text-[13px] font-semibold text-white disabled:opacity-60"
              style={{ background: '#14532d' }}>
        {ocupado ? <CircleNotch size={14} className="animate-spin" /> : <ArrowUUpLeft size={14} weight="bold" />} Mandar de volta para Proprietários
      </button>
      <button type="button" onClick={aoDevolverCorretor} disabled={ocupado}
              title="É corretor: a conversa sai da Captação e volta para o número dela como Corretor"
              className="self-start flex items-center gap-1.5 h-8 px-3 rounded-lg text-[13px] font-semibold disabled:opacity-60"
              style={{ border: '1px solid #14532d', color: 'var(--wa-text)' }}>
        <ArrowUUpLeft size={14} weight="bold" /> Mandar de volta para Corretor
      </button>
    </div>
  )
}

export default function ChatCaptacao() {
  const { setLeads } = useLeadsContext()
  const ids = useConversasDeCaptacao()
  const contexto = useContextoDaCaptacao()
  const [devolvendo, setDevolvendo] = useState('')
  const pertence = useCallback((l: LeadWithOwner) => ehDeCaptacao(l, ids), [ids])

  const devolver = async (l: LeadWithOwner, para: 'proprietario' | 'corretor' = 'proprietario') => {
    setDevolvendo(l.id)
    try {
      if (getLinhaWhatsapp(l) === 'parceria') {
        const r = await fetch(`/api/leads/${l.id}/contato`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ etapa: para === 'corretor' ? 'todos' : 'proprietarios' }),
        })
        if (!r.ok) { const j = await r.json().catch(() => ({})); throw new Error(j.error || j.message || 'Não consegui mudar a etapa.') }
      }
      const o = await organizar(l.id, { tipo: para, captacao: false })
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
      void recarregarCaptacao()
    } catch (e: any) {
      window.alert(e?.message || 'Não consegui mandar de volta.')
    } finally { setDevolvendo('') }
  }

  return (
    <ChatJuntado titulo="Captação" subtitulo="Cadastros incompletos e donos chamados pela OLX · cada conversa responde pelo número dela"
                 pertence={pertence} chaveAbas="crm:abas-captacao" vazio="Nenhuma conversa de captação agora."
                 cadastrar={(l) => {
                   const c = contexto[l.id]
                   return { linkInicial: c?.fonte === 'olx' ? c.url : undefined }
                 }}
                 topoDoCard={(l) => <Contexto c={contexto[l.id]} ocupado={devolvendo === l.id} aoDevolver={() => void devolver(l)}
                                              aoDevolverCorretor={() => void devolver(l, 'corretor')} />}
                 etapaDoCard={(l) => <TipoDoContato lead={l} aoMudar={(custom) => setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: custom } : x)))} />}
                 menu={(lead, fechar) => (
                   <>
                     <button type="button" className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3"
                             title="Depois de finalizar o cadastro: a conversa sai da Captação e volta para Proprietários no número dela"
                             onClick={() => { fechar(); void devolver(lead) }}>
                       <ArrowUUpLeft size={17} style={{ color: 'var(--wa-icon)' }} /> Mandar de volta para Proprietários
                     </button>
                     <button type="button" className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3"
                             title="É corretor: a conversa sai da Captação e volta para o número dela como Corretor"
                             onClick={() => { fechar(); void devolver(lead, 'corretor') }}>
                       <ArrowUUpLeft size={17} style={{ color: 'var(--wa-icon)' }} /> Mandar de volta para Corretor
                     </button>
                   </>
                 )} />
  )
}
