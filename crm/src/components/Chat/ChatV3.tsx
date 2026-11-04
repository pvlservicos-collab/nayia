'use client'

/**
 * O ATENDIMENTO DA V3 (Pedro, 04/11/2026): um WhatsApp só juntando Leads (8595) e Parceria (9445), em filas e etapas.
 * O pedido do desenho ("deixar fácil identificar de qual fila é o contato e quem está respondendo agora, removendo
 * informação repetida; não mude a lógica de negócio nem remova funcionalidades; só reorganize a interface"):
 *
 *   filtros     Todas / Locação (Diego) / Venda (Rayssa) / Corretores (Nay), com a bolinha da cor da fila
 *   card        3 linhas: nome e hora; a prévia; a barrinha das etapas (60 px), o nome da etapa e o selo de quem
 *               responde (IA roxo, a pessoa verde). O avatar tem o anel da cor da fila. Sem etiquetas (as anotações ficam
 *               no card do contato, à direita); o alfinete só se a conversa estiver fixada
 *   cabeçalho   anel no avatar; o nome e a pílula do tipo (Lead locação / Lead venda / Corretor); embaixo o telefone e o
 *               resumo da ficha (o pedido de agora da Nay: quartos, teto, bairros; do corretor, o CRECI); os botões de sempre
 *   etapas      a barra das 5 etapas embaixo do cabeçalho; clicar muda a etapa à mão (custom_attributes.etapa_v3, rota
 *               organizar); clicar na etapa escolhida à mão volta ao automático
 *   balões      IA roxo com o robô, humano verde com a pessoa (ou o celular): ActivityTimeline no modo v3
 *   quem responde  UMA barra em cima da caixa de mensagem: "IA respondendo · sai pelo Leads 8595" com Assumir, ou
 *               "Fulano está respondendo" com Devolver à IA (no lugar do "Sai pelo..." e do Pausar IA)
 *
 * A lógica é a de sempre: cada conversa é da linha dela (crm/CLAUDE.md) e a resposta sai pelo número dela; a Nay que atende
 * segue a origem. Assumir e Devolver usam o que já existe: no Leads a etapa manual da captação (com_o_tel cala a Nay Leads,
 * todos a solta: crm_captacao_etapa_manual, 398); na Parceria o Parar Nay / Nay voltar (crm_nay_parar / crm_nay_voltar). Os
 * dois também gravam quem assumiu (responsavel_v2, a regra da v2).
 *
 * AS ETAPAS AUTOMÁTICAS saem do passo da Nay Leads (520): Começar (perguntando o perfil), Filtrado (busca feita), Em
 * atendimento (imóveis enviados), Enviado opção (pediu visita), Visitas (confirmada, ou na etapa Visita). Na Parceria:
 * Visitas ou Em atendimento.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { CaretDown, Check, CircleNotch, LockSimple, PushPin, Robot, User, WhatsappLogo } from '@phosphor-icons/react'
import { useAuth, useOrganizationMembers } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { useCorretoresDaCaptacao } from '@/hooks/useCorretoresDaCaptacao'
import { useOlxClientes, mudarEtapaOlx } from '@/hooks/useOlxClientes'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useEquipeV2 } from '@/hooks/useEquipeV2'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import { etapaDaParceria } from '@/lib/etapaDaParceria'
import { tipoEscolhido, tipoDoLead, TIPOS_DO_LEAD, CORPO_DO_TIPO, NOME_DA_LINHA, type TipoDoLead } from '@/lib/organizacaoDoLead'
import { montarAtendentes } from '@/lib/atendentes'
import { primeiroNome, responsavelV2, usePapelV2 } from '@/lib/versaoDoCrm'
import { ModoV3, FILAS_V3, ETAPAS_V3, CLASSE_DO_AUTOR, indiceDaEtapa, NOME_DA_ETAPA, type FilaV3 } from '@/lib/modoV3'
import { formatPhone } from '@/lib/utils'
import type { LeadWithOwner } from '@/lib/types'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import ChatJuntado from './ChatJuntado'
import type { PainelV3 } from './PainelContatoCaptacao'
import OrganizarConversa, { EnviarParaDaParceria, organizar, type Organizado } from './OrganizarConversa'

const CINZA = '#888780'
const NUMERO: Record<string, string> = { captacao: 'Leads 8595', parceria: 'Parceria 9445' }
type Responde = { tipo: 'ia' | 'humano'; nome: string }

/** o login Tel (administrador de verdade): a v3 é só dele, por enquanto */
export function useEhTel(): boolean {
  const { profileName, user } = useAuth()
  const papel = usePapelV2()
  return papel.adminDeVerdade && primeiroNome(profileName || user?.name) === 'pedro'
}

const iniciais = (t: string) => t.trim().split(/\s+/).slice(0, 2).map((p) => p.charAt(0).toUpperCase()).join('') || '?'
const reais = (v: number) => v >= 1e6 ? `R$ ${(v / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`
  : v >= 1000 ? `R$ ${(v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil` : `R$ ${v}`

/** a barrinha curta das etapas da Nay (card): até a etapa de agora com a cor de cada uma, o resto cinza */
function BarrinhaCurta({ atual }: { atual: number }) {
  return (
    <span className="flex items-center gap-[2px] w-[60px] flex-shrink-0 py-[3px]">
      {ETAPAS_V3.map((e, i) => (
        <span key={e.chave} title={e.rotulo} className="h-[6px] flex-1 rounded-full cursor-default"
              style={{ background: i <= atual ? e.cor : 'var(--wa-row-selected)' }} />
      ))}
    </span>
  )
}

function Selo({ r }: { r: Responde }) {
  return (
    <span className={`${CLASSE_DO_AUTOR[r.tipo]} v3-selo flex-shrink-0 rounded-full px-1.5 text-[11px] font-medium leading-[16px]`}
          title={r.tipo === 'ia' ? 'A Nay (IA) está respondendo' : `${r.nome} está respondendo`}>{r.tipo === 'ia' ? 'IA' : r.nome}</span>
  )
}

/** o card da lista: exatamente 3 linhas */
function CardV3({ l, hora, aberta, abrir, menu, cor, etapa, tipo, r }: {
  l: LeadWithOwner; hora: string; aberta: boolean; abrir: () => void; menu: (e: React.MouseEvent) => void
  /** só lead tem etapa (a da Nay); corretor e proprietário mostram o tipo no lugar da barrinha */
  cor: string; etapa: { i: number; nome: string } | null; tipo: string; r: Responde
}) {
  const nome = (l.title || '').trim() || formatPhone(l.phone || '') || 'Sem nome'
  const naoLida = !!l.is_unread
  return (
    <button type="button" data-lead-id={l.id} onClick={abrir} onContextMenu={menu}
            className="w-full flex items-center gap-3 px-3 py-2.5 text-left"
            style={{ background: aberta ? 'var(--wa-row-selected)' : undefined, borderBottom: '1px solid var(--wa-divider)' }}>
      <span className="w-11 h-11 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center text-[14px] font-medium"
            style={{ background: 'var(--wa-row-selected)', color: 'var(--wa-text-2)', boxShadow: `0 0 0 2px ${cor}` }}>
        {l.avatar_url ? <img src={l.avatar_url} alt="" className="w-full h-full object-cover" /> : iniciais(nome)}
      </span>
      <span className="flex-1 min-w-0 flex flex-col gap-[3px]">
        <span className="flex items-center gap-2">
          <span className="flex-1 truncate text-[15px]" style={{ color: 'var(--wa-text)', fontWeight: naoLida ? 600 : 400 }}>{nome}</span>
          <span className="text-[12px] flex-shrink-0" style={{ color: naoLida ? 'var(--wa-green)' : 'var(--wa-text-2)' }}>{hora}</span>
        </span>
        <span className="flex items-center gap-1.5">
          <span className="flex-1 truncate text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{l.last_message_content || 'Sem mensagens'}</span>
          {l.is_pinned && <PushPin size={13} weight="fill" style={{ color: 'var(--wa-text-2)' }} aria-label="Fixada" />}
          {naoLida && <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: 'var(--wa-green)' }} aria-label="Não lida" />}
        </span>
        <span className="flex items-center gap-2">
          {etapa && <BarrinhaCurta atual={etapa.i} />}
          <span className="flex-1 truncate text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{etapa ? etapa.nome : tipo}</span>
          <Selo r={r} />
        </span>
      </span>
    </button>
  )
}

/** O NÚMERO DA CONVERSA (Pedro, 04/11: "ao lado do nome, de forma discreta, por qual número essa conversa acontece"):
 *  o ícone do WhatsApp e o nome do número, 11 px, cor secundária, sem fundo */
export function NumeroDaConversa({ l }: { l: LeadWithOwner }) {
  const linha = getLinhaWhatsapp(l)
  if (!linha) return null
  return (
    <span className="inline-flex items-center gap-[3px] text-[11px] font-normal flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}
          title={`Esta conversa é pelo número ${NOME_DA_LINHA[linha]}`}>
      <WhatsappLogo size={12} />{NOME_DA_LINHA[linha]}
    </span>
  )
}

export type Avisar = (texto: string, desfazer?: () => Promise<void>) => void

/** A PÍLULA DO TIPO (Pedro, 04/11): clica e troca (Lead locação, Lead venda, Corretor, Proprietário, Administração). A troca
 *  é manual e fica travada: só outra troca manual muda (o cadeado mostra quem e quando). Depois, "Tipo alterado · Desfazer". */
export function PilulaDoTipo({ l, atual, cor, aoMudar, avisar }: {
  l: LeadWithOwner; atual: TipoDoLead; cor: string; aoMudar: (o: Organizado) => void; avisar: Avisar
}) {
  const [aberto, setAberto] = useState(false)
  const [salvando, setSalvando] = useState(false)
  const ca = (l.custom_attributes || {}) as any
  const manual = !!tipoEscolhido(l)
  const nome = (t: TipoDoLead) => (t === 'locacao' ? 'Lead locação' : t === 'vendas' ? 'Lead venda' : TIPOS_DO_LEAD.find((x) => x.chave === t)?.nome || 'Escolher tipo')
  const quando = ca.tipo_contato_em
    ? new Date(ca.tipo_contato_em).toLocaleString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
    : null
  const dica = `Definido manualmente${ca.tipo_contato_por ? ` por ${String(ca.tipo_contato_por).split(' ')[0]}` : ''}${quando ? ` em ${quando}` : ''}`
  const mudar = async (novo: Exclude<TipoDoLead, ''>) => {
    setAberto(false)
    if (novo === atual) return
    const antes: Record<string, unknown> = manual && atual ? CORPO_DO_TIPO[atual as Exclude<TipoDoLead, ''>] : { tipo: null }
    setSalvando(true)
    try {
      // virou corretor: sai de quem atendia o lead (Diego/Rayssa) e volta à regra do número (a fila Corretores)
      aoMudar(await organizar(l.id, { ...CORPO_DO_TIPO[novo], ...(novo === 'corretor' ? { responsavel: null } : {}) }))
      avisar(`Tipo alterado para ${nome(novo)}`, async () => { aoMudar(await organizar(l.id, antes)) })
    } catch (e: any) { window.alert(e?.message || 'Não consegui mudar o tipo.') } finally { setSalvando(false) }
  }
  return (
    <span className="relative inline-flex items-center gap-1 flex-shrink-0">
      <button type="button" onClick={() => setAberto((x) => !x)} disabled={salvando} aria-expanded={aberto}
              title="Tipo do contato: clique para trocar"
              className="inline-flex items-center gap-1 rounded-full px-2 h-[20px] text-[11.5px] font-medium disabled:opacity-60"
              style={{ color: cor, background: `${cor}22`, border: `1px solid ${cor}66` }}>
        {salvando && <CircleNotch size={11} className="animate-spin" />}{nome(atual)}<CaretDown size={10} weight="bold" />
      </button>
      {manual && (
        <span title={dica} aria-label={dica} className="inline-flex" style={{ color: 'var(--wa-text-2)' }}><LockSimple size={12} weight="fill" /></span>
      )}
      {aberto && (
        <span className="absolute left-0 top-full mt-1 z-50 min-w-[170px] rounded-lg py-1 shadow-xl flex flex-col"
              style={{ background: 'var(--wa-menu, var(--wa-panel))', border: '1px solid var(--wa-divider)' }}>
          {TIPOS_DO_LEAD.map((t) => (
            <button key={t.chave} type="button" onClick={() => void mudar(t.chave)}
                    className="flex items-center gap-2 px-3 py-1.5 text-[13px] text-left hover:bg-[var(--wa-row-hover)]" style={{ color: 'var(--wa-text)' }}>
              <span className="flex-1">{nome(t.chave)}</span>{t.chave === atual && <Check size={13} weight="bold" />}
            </button>
          ))}
        </span>
      )}
    </span>
  )
}

/** A BARRA DAS ETAPAS DO LEAD = as etapas reais da Nay Leads (uma fonte só). Clicar muda a etapa dela na hora (a mesma
 *  gravação do card antigo; quem estava com a equipe e ganha uma etapa volta para a Nay, como no Salvar de antes) e aparece
 *  "Etapa alterada · Desfazer". */
export function BarraDasEtapas({ l, etapa, comAEquipe, avisar }: { l: LeadWithOwner; etapa: string; comAEquipe: boolean; avisar: Avisar }) {
  const [salvando, setSalvando] = useState<string | null>(null)
  const atual = indiceDaEtapa(etapa)
  const soltarANay = () => fetch(`/api/leads/${l.id}/captacao-etapa`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'todos' }),
  }).catch(() => undefined)
  const escolher = async (chave: string) => {
    if (chave === etapa || salvando) return
    setSalvando(chave)
    const erro = await mudarEtapaOlx(l.phone || '', chave as any)
    if (!erro && comAEquipe) await soltarANay()
    setSalvando(null)
    if (erro) { window.alert(`Não mudou a etapa: ${erro}`); return }
    // 'nova' (a Nay ainda não começou) não é uma etapa que se grava: aí não há o que desfazer
    const voltaPara = etapa && etapa !== 'nova' ? etapa : null
    avisar(`Etapa alterada para ${NOME_DA_ETAPA[chave] || chave}`, voltaPara
      ? async () => { const e = await mudarEtapaOlx(l.phone || '', voltaPara as any); if (e) throw new Error(e) }
      : undefined)
  }
  return (
    <div className="flex-shrink-0 grid grid-cols-4 gap-1.5 px-3 pt-2 pb-1.5">
      {ETAPAS_V3.map((e, i) => (
        <button key={e.chave} type="button" onClick={() => void escolher(e.chave)} disabled={salvando !== null}
                title={`Mudar a etapa da Nay para ${e.rotulo}`} className="flex flex-col items-center gap-1 min-w-0 disabled:opacity-60">
          <span className="h-[5px] w-full rounded-full" style={{ background: e.cor, opacity: i <= atual ? 1 : 0.3 }} />
          <span className="text-[12px] truncate flex items-center gap-1"
                style={{ color: i === atual ? 'var(--wa-text)' : 'var(--wa-text-2)', fontWeight: i === atual ? 500 : 400 }}>
            {salvando === e.chave && <CircleNotch size={11} className="animate-spin" />}{e.curto}
          </span>
        </button>
      ))}
    </div>
  )
}

/** o aviso de baixo, com Desfazer (some sozinho em 7 s) */
function AvisoComDesfazer({ aviso, fechar }: { aviso: { texto: string; desfazer?: () => Promise<void> } | null; fechar: () => void }) {
  const [desfazendo, setDesfazendo] = useState(false)
  useEffect(() => { if (!aviso) return; const t = setTimeout(fechar, 7000); return () => clearTimeout(t) }, [aviso, fechar])
  if (!aviso) return null
  return (
    <div className="fixed bottom-5 left-1/2 -translate-x-1/2 z-[80] flex items-center gap-3 px-4 h-10 rounded-lg shadow-xl text-[13px]"
         style={{ background: 'var(--wa-text)', color: 'var(--wa-panel)' }} role="status">
      {aviso.texto}
      {aviso.desfazer && (
        <button type="button" disabled={desfazendo} className="font-semibold underline disabled:opacity-60"
                onClick={async () => {
                  setDesfazendo(true)
                  try { await aviso.desfazer!() } catch (e: any) { window.alert(e?.message || 'Não consegui desfazer.') }
                  finally { setDesfazendo(false); fechar() }
                }}>
          {desfazendo ? 'Desfazendo…' : 'Desfazer'}
        </button>
      )}
    </div>
  )
}

/** embaixo do nome no alto: o telefone e o resumo da ficha (o pedido de agora; do corretor, o CRECI) */
function SubtituloV3({ l, ehLead, creci }: { l: LeadWithOwner; ehLead: boolean; creci: string | null }) {
  const [resumo, setResumo] = useState<string | null>(null)
  useEffect(() => {
    setResumo(null)
    if (!ehLead) return
    let vivo = true
    fetch(`/api/leads/${l.id}/buscas`).then((r) => (r.ok ? r.json() : null)).then((j) => {
      const f = j?.ativa?.filtros
      if (!vivo || !f) return
      const onde = Array.isArray(f.bairros) && f.bairros.length ? f.bairros.slice(0, 2).join(', ') : f.condominio || null
      const partes = [f.quartos ? `${f.quartos} quarto${Number(f.quartos) > 1 ? 's' : ''}` : null, f.teto ? `até ${reais(Number(f.teto))}` : null, onde]
      setResumo(partes.filter(Boolean).join(' · ') || null)
    }).catch(() => undefined)
    return () => { vivo = false }
  }, [l.id, ehLead])
  const extra = ehLead ? resumo : creci ? `CRECI ${creci}` : null
  return <>{[formatPhone(l.phone || ''), extra].filter(Boolean).join(' · ')}</>
}

/** a barra de quem responde, em cima da caixa de mensagem: IA (roxo) com Assumir, ou a pessoa (verde) com Devolver à IA */
function QuemResponde({ l, r, aoMudar, noPainel }: { l: LeadWithOwner; r: Responde; aoMudar: (r: Responde, o?: Organizado) => void; noPainel?: boolean }) {
  const { profileName, user } = useAuth()
  const [ocupado, setOcupado] = useState(false)
  const [pausa, setPausa] = useState<{ quem: string } | null>(null)
  const linha = getLinhaWhatsapp(l) || ''
  // o Leads também pausa sozinho 30 min depois que alguém da equipe escreve (pausa-da-nay): conta como a pessoa respondendo
  useEffect(() => {
    setPausa(null)
    if (linha !== 'captacao' || r.tipo === 'humano') return
    let vivo = true
    fetch(`/api/leads/${l.id}/pausa-da-nay`).then((x) => (x.ok ? x.json() : null)).then((j) => {
      if (vivo && j?.ate && Date.parse(j.ate) > Date.now()) setPausa({ quem: String(j.quem || 'Equipe').split(/\s+/)[0] })
    }).catch(() => undefined)
    return () => { vivo = false }
  }, [l.id, linha, r.tipo])
  const agora: Responde = r.tipo === 'ia' && pausa ? { tipo: 'humano', nome: pausa.quem } : r
  const eu = (() => { const p = primeiroNome(profileName || user?.name); return p ? p.charAt(0).toUpperCase() + p.slice(1) : 'Equipe' })()
  const postar = (url: string, corpo: unknown) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
    .then(async (x) => { if (!x.ok) { const j = await x.json().catch(() => ({})); throw new Error(j.error || j.message || 'Não consegui.') } })
  const assumir = async () => {
    setOcupado(true)
    try {
      await (linha === 'parceria' ? postar(`/api/leads/${l.id}/nay`, { acao: 'parar' }) : postar(`/api/leads/${l.id}/captacao-etapa`, { etapa: 'com_o_tel' }))
      aoMudar({ tipo: 'humano', nome: eu }, await organizar(l.id, { responsavel: { nome: eu } }))
    } catch (e: any) { window.alert(e?.message || 'Não consegui assumir.') } finally { setOcupado(false) }
  }
  const devolver = async () => {
    setOcupado(true)
    try {
      await (linha === 'parceria' ? postar(`/api/leads/${l.id}/nay`, { acao: 'voltar' }) : postar(`/api/leads/${l.id}/captacao-etapa`, { etapa: 'todos' }))
      setPausa(null)
      aoMudar({ tipo: 'ia', nome: 'IA' }, await organizar(l.id, { responsavel: null }))
    } catch (e: any) { window.alert(e?.message || 'Não consegui devolver à IA.') } finally { setOcupado(false) }
  }
  return (
    <div className={`${CLASSE_DO_AUTOR[agora.tipo]} v3-selo relative z-10 flex-shrink-0 ${noPainel ? '' : 'mx-3 sm:mx-5 mt-1.5'} px-3 h-9 rounded-lg flex items-center gap-2 text-[13px]`}>
      {agora.tipo === 'ia' ? <Robot size={16} weight="fill" /> : <User size={16} weight="fill" />}
      <span className="flex-1 truncate">
        {agora.tipo === 'ia' ? 'IA respondendo' : `${agora.nome} está respondendo`} · sai pelo {NUMERO[linha] || linha}
      </span>
      <button type="button" disabled={ocupado} onClick={() => void (agora.tipo === 'ia' ? assumir() : devolver())}
              className="flex items-center gap-1 h-7 px-2.5 rounded-md text-[12.5px] font-medium disabled:opacity-60"
              style={{ border: '1px solid currentColor' }}>
        {ocupado && <CircleNotch size={12} className="animate-spin" />}{agora.tipo === 'ia' ? 'Assumir' : 'Devolver à IA'}
      </button>
    </div>
  )
}

export default function ChatV3() {
  const { loading, organizationId } = useAuth()
  const ehTel = useEhTel()
  const { leads, setLeads } = useLeadsContext()
  const { ehProprietario, ehVisita, ehLocacao } = usePapelDoContato(true, true)
  const { emFechamento, podeVer } = useFechamentoV2()
  const corretoresDoLeads = useCorretoresDaCaptacao(true)
  const olx = useOlxClientes(true)
  const { marcas } = useParceriaMarcas(true)
  const equipeV2 = useEquipeV2(true)
  const { members } = useOrganizationMembers(organizationId || '')
  const equipe = useMemo(() => montarAtendentes(members || []), [members])
  // o que Assumir / Devolver acabou de fazer (até a próxima leitura das marcas e dos clientes confirmar)
  const [mudado, setMudado] = useState<Record<string, Responde>>({})
  const [aviso, setAviso] = useState<{ texto: string; desfazer?: () => Promise<void> } | null>(null)
  const avisar: Avisar = useCallback((texto, desfazer) => setAviso({ texto, desfazer }), [])
  const fecharAviso = useCallback(() => setAviso(null), [])
  // 04/11 (Pedro: "no número dele quem está respondendo é a equipe e na v3 tá IA"): quem mandou a ÚLTIMA mensagem nossa;
  // gente (pelo CRM ou pelo celular) vale como a pessoa respondendo, mesmo que a Nay não esteja pausada
  const [humanos, setHumanos] = useState<Record<string, { nome: string; celular: boolean }>>({})
  useEffect(() => {
    if (!ehTel) return
    let vivo = true
    const ler = () => fetch('/api/linhas/quem-responde').then((r) => (r.ok ? r.json() : null)).then((j) => { if (vivo && j?.humanos) setHumanos(j.humanos) }).catch(() => undefined)
    void ler()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler() }, 30_000)
    return () => { vivo = false; clearInterval(t) }
  }, [ehTel])

  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria').map((l) => fim8(l.phone)).filter(Boolean)), [leads])

  /* AS ABAS SÃO EXCLUSIVAS (Pedro, 04/11: "se ele está em fechamento não é para estar em atendimento; as únicas abas que não
     são exclusivas é Proprietários, o resto ele só pode estar lá até ser mandado de volta"): quem está em Fechamento, em
     Visita ou é Administração fica só na aba dele (as da barra de cima) e sai do Atendimento */
  const daTela = useCallback((l: LeadWithOwner): boolean => {
    const linha = getLinhaWhatsapp(l)
    if (l.is_group || (linha !== 'captacao' && linha !== 'parceria')) return false
    if (linha === 'captacao' && pelaParceria.has(fim8(l.phone))) return false
    if (!podeVer(l) || emFechamento(l) || ehVisita(l) || tipoEscolhido(l) === 'administracao') return false
    return true
  }, [pelaParceria, podeVer, emFechamento, ehVisita])

  /** o tipo de agora: o escolhido à mão; senão o que a lista deduz (corretor na Parceria, dono, locação ou venda) */
  const tipoDe = useCallback((l: LeadWithOwner): TipoDoLead => {
    const t = tipoDoLead(l, getLinhaWhatsapp(l) === 'captacao', (f) => olx[f]?.finalidade)
    if (t && tipoEscolhido(l)) return t
    if (ehProprietario(l)) return 'proprietario'
    if (getLinhaWhatsapp(l) === 'parceria' || corretoresDoLeads.has(fim8(l.phone))) return 'corretor'
    return ehLocacao(l) ? 'locacao' : 'vendas'
  }, [olx, ehProprietario, corretoresDoLeads, ehLocacao])

  /** a fila pelo tipo (04/11, Pedro: o Evandro é proprietário, não corretor): Administração fica só em Todas, com o anel cinza */
  const filaDe = useCallback((l: LeadWithOwner): FilaV3 | null => {
    if (!daTela(l)) return null
    const t = tipoDe(l)
    if (t === 'proprietario') return 'proprietarios'
    if (t === 'corretor') return 'corretores'
    if (t === 'administracao') return null
    return t === 'locacao' ? 'locacao' : 'venda'
  }, [daTela, tipoDe])

  /** a etapa da Nay Leads, só para lead (locação ou venda); corretor e proprietário não entram no funil de lead */
  const etapaNay = useCallback((l: LeadWithOwner): string | null => {
    const f = filaDe(l)
    if (f !== 'locacao' && f !== 'venda') return null
    return String(olx[fim8(l.phone)]?.etapa || 'nova')
  }, [filaDe, olx])

  /** quem responde agora: a pessoa quando a Nay está parada nesta conversa; senão a IA */
  const respondeDe = useCallback((l: LeadWithOwner): Responde => {
    if (mudado[l.id]) return mudado[l.id]
    const marca = marcas[l.id]
    const parada = getLinhaWhatsapp(l) === 'parceria' ? !!marca?.telAtendendo : !!olx[fim8(l.phone)]?.humano
    if (!parada) return humanos[l.id] ? { tipo: 'humano', nome: humanos[l.id].nome || 'Equipe' } : { tipo: 'ia', nome: 'IA' }
    const r = responsavelV2(l as any, equipeV2)
    const doMotivo = /^(\p{L}+):/u.exec(String(marca?.telMotivo || ''))?.[1]
    return { tipo: 'humano', nome: r && !r.nay ? r.nome : doMotivo || 'Equipe' }
  }, [mudado, marcas, olx, equipeV2, humanos])

  const aplicar = useCallback((leadId: string, o: Organizado) => {
    setLeads((p) => p.map((x) => (x.id === leadId ? {
      ...x, custom_attributes: o.custom_attributes,
      ...(o.last_activity_at ? { last_activity_at: new Date(o.last_activity_at).toISOString() } : {}),
      ...(typeof o.is_unread === 'boolean' ? { is_unread: o.is_unread } : {}),
    } : x)))
  }, [setLeads])

  const etapas = useMemo(() => [
    { chave: 'todas', rotulo: 'Todas', cor: CINZA, casa: daTela },
    ...(Object.keys(FILAS_V3) as FilaV3[]).map((f) => ({
      chave: f, rotulo: FILAS_V3[f].rotulo, quem: FILAS_V3[f].quem, cor: FILAS_V3[f].cor, casa: (l: LeadWithOwner) => filaDe(l) === f,
    })),
  ], [daTela, filaDe])

  if (loading) return null
  if (!ehTel) return <NotAuthorized />

  const rotuloDoTipo = (l: LeadWithOwner) => { const f = filaDe(l); return f ? FILAS_V3[f].tipo : 'Administração' }
  const corDe = (l: LeadWithOwner) => { const f = filaDe(l); return f ? FILAS_V3[f].cor : CINZA }
  return (
    <ModoV3.Provider value={true}>
      <div className="chat-theme h-full min-h-0">
        <ChatJuntado titulo="Atendimento" subtitulo="Leads e Parceria num lugar só · a resposta sai pelo número de cada conversa"
                     pertence={daTela} etapas={etapas} etapasEmLista semFaixaDaLinha chaveAbas="crm:abas-v3"
                     vazio="Nenhuma conversa aqui."
                     cadastrar={() => ({})}
                     painelV3={(l): PainelV3 => {
                       const cor = corDe(l)
                       return {
                         anel: cor,
                         numero: <NumeroDaConversa l={l} />,
                         pilula: <PilulaDoTipo l={l} atual={tipoDe(l)} cor={cor} aoMudar={(o) => aplicar(l.id, o)} avisar={avisar} />,
                         quemResponde: <QuemResponde key={`painel-${l.id}`} l={l} r={respondeDe(l)} noPainel
                                                     aoMudar={(x, o) => { setMudado((m) => ({ ...m, [l.id]: x })); if (o) aplicar(l.id, o) }} />,
                         etapa: etapaNay(l) ? <BarraDasEtapas l={l} etapa={etapaNay(l)!} comAEquipe={!!olx[fim8(l.phone)]?.humano} avisar={avisar} /> : null,
                         ehLead: !!etapaNay(l),
                       }
                     }}
                     itemDaLista={(l, x) => <CardV3 l={l} hora={x.hora} aberta={x.aberta} abrir={x.abrir} menu={x.menu}
                                                    cor={corDe(l)} r={respondeDe(l)} tipo={rotuloDoTipo(l)}
                                                    etapa={etapaNay(l) ? { i: indiceDaEtapa(etapaNay(l)), nome: NOME_DA_ETAPA[etapaNay(l)!] || etapaNay(l)! } : null} />}
                     naConversa={{
                       anel: corDe,
                       pilula: (l) => {
                         const f = filaDe(l)
                         const cor = f ? FILAS_V3[f].cor : CINZA
                         return { texto: '', cor, no: <><NumeroDaConversa l={l} /><PilulaDoTipo l={l} atual={tipoDe(l)} cor={cor} aoMudar={(o) => aplicar(l.id, o)} avisar={avisar} /></> }
                       },
                       subtitulo: (l) => <SubtituloV3 l={l} ehLead={getLinhaWhatsapp(l) === 'captacao' && (filaDe(l) === 'locacao' || filaDe(l) === 'venda')}
                                                      creci={marcas[l.id]?.creci || null} />,
                       abaixoDoTopo: (l) => etapaNay(l)
                         ? <BarraDasEtapas l={l} etapa={etapaNay(l)!} comAEquipe={!!olx[fim8(l.phone)]?.humano} avisar={avisar} />
                         : null,
                       rodape: (l) => <QuemResponde key={l.id} l={l} r={respondeDe(l)}
                                                    aoMudar={(r, o) => { setMudado((m) => ({ ...m, [l.id]: r })); if (o) aplicar(l.id, o) }} />,
                       organizar: (l) => getLinhaWhatsapp(l) === 'parceria'
                         ? <EnviarParaDaParceria lead={l} aoMudar={(o) => aplicar(l.id, o)} />
                         : <OrganizarConversa lead={l} tipoDeduzido={null} equipe={equipe} naLocacao={ehLocacao(l)} semTipo
                                              aoMudar={(o) => aplicar(l.id, o)} />,
                     }} />
      </div>
      <AvisoComDesfazer aviso={aviso} fechar={fecharAviso} />
    </ModoV3.Provider>
  )
}
