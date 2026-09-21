'use client'

/**
 * Coluna fixa "Fonte:" — a primeira do Kanban, à esquerda de todas as etapas.
 *
 * Ela NÃO é uma etapa do pipeline, e a diferença é proposital em três pontos:
 *   - não recebe drop nem participa do arrastar (não é um estado do lead);
 *   - não pode ser editada nas configurações junto com as outras colunas;
 *   - tem tratamento visual próprio (fundo com degradê, borda de acento à
 *     esquerda, cabeçalho "Fonte:") pra ficar claro que é outra coisa.
 *
 * Dentro dela, um card por fonte de lead. Cada card lista os leads que entraram
 * por aquela fonte, mais recente em cima. A lista rola DENTRO do card — o card
 * tem altura fixa e nunca cresce com o número de leads, que é o que manteria a
 * coluna alinhada com as outras.
 *
 * Clicar num minicard acende o card daquele lead na coluna de status onde ele
 * está (ver `onHighlightLead` / `highlightedLeadId` no PipelineBoard).
 */

import { useMemo, useState } from 'react'
import { MagnifyingGlass, X, CaretDown, Plus } from '@phosphor-icons/react'
import { LeadWithOwner } from '@/lib/types'
import { formatPhone } from '@/lib/utils'
import { LEAD_SOURCES, ACQUISITION_SOURCE_ORDER, type LeadSourceKey } from '@/lib/leadSources'
import { useLeadsContext } from '@/contexts/LeadsContext'
import NovoLeadManualModal from './NovoLeadManualModal'
import TabelaCadastroManual from './TabelaCadastroManual'
import { momentoPorChave } from '@/lib/momentos'
import { EQUIPE_ATENDIMENTO } from '@/lib/atendentes'

/**
 * Cor de identificação de cada fonte — só na coluna Fonte, pra distinguir os
 * cards. O mapa cobre todas as fontes, mas a coluna só desenha as de aquisição
 * (ACQUISITION_SOURCE_ORDER): lista importada de planilha não é "por onde o
 * lead está entrando", que é a pergunta que esta coluna responde.
 */
const SOURCE_COLORS: Record<LeadSourceKey, string> = {
  agenda_ascensao: '#c98500',
  site_evento: '#3987e5',
  indicacao: '#3aa76d',
  agenda_antigos: '#7b7b76',
}

interface SourceRailProps {
  leads: LeadWithOwner[]
  /** Nome da etapa por id — o minicard mostra em que status o lead está. */
  stageNameById: Record<string, string>
  stageColorById: Record<string, string>
  highlightedLeadId: string | null
  onHighlightLead: (leadId: string) => void
}

/**
 * De qual canal de aquisição o lead veio, ou null.
 *
 * `custom_attributes.lead_source` é gravado pela ingestão (src/lib/ingest.ts) e
 * também pela importação por planilha. Só interessa aqui quem veio de um canal
 * ao vivo: lead de importação, cadastro manual ou WhatsApp não aparece nesta
 * coluna, que é sobre por onde o lead está ENTRANDO.
 *
 * Checa contra ACQUISITION_SOURCE_ORDER, e não contra LEAD_SOURCES: o segundo
 * inclui a lista importada, e devolver ela aqui quebrava a montagem dos grupos
 * abaixo — que só cria balde pras fontes de aquisição.
 */
function sourceOf(lead: LeadWithOwner): LeadSourceKey | null {
  const value = (lead.custom_attributes as Record<string, unknown> | undefined)?.lead_source
  if (typeof value !== 'string') return null
  return (ACQUISITION_SOURCE_ORDER as string[]).includes(value) ? (value as LeadSourceKey) : null
}

function MiniCard({
  lead,
  stageName,
  stageColor,
  isHighlighted,
  onClick,
}: {
  lead: LeadWithOwner
  stageName: string | null
  stageColor: string | null
  isHighlighted: boolean
  onClick: () => void
}) {
  const atributos = (lead.custom_attributes ?? {}) as Record<string, unknown>
  // "Qual WhatsApp" do cadastro manual: marcação de quem é o lead, sem efeito
  // no envio (a mensagem sai sempre do número do CRM).
  const responsavel = typeof atributos.whatsapp_responsavel === 'string' ? atributos.whatsapp_responsavel : null
  const corDoResponsavel = EQUIPE_ATENDIMENTO.find((p) => p.nome === responsavel)?.cor
  const momento = momentoPorChave(atributos.phase ?? atributos.fase)

  return (
    <button
      type="button"
      onClick={onClick}
      className={`w-full text-left rounded-lg px-2.5 py-2 border transition-colors ${
        isHighlighted
          ? 'border-accent/50 bg-accent/10'
          : 'border-white/[0.07] bg-white/[0.03] hover:bg-white/[0.07]'
      }`}
    >
      <p className="text-[12px] font-semibold text-ink truncate leading-tight">{lead.title}</p>
      <div className="flex items-center justify-between gap-2 mt-1">
        <span className="text-[10px] text-muted tabular-nums truncate">
          {lead.phone ? formatPhone(lead.phone) : '—'}
        </span>
        {stageName && (
          <span
            className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full flex-shrink-0 max-w-[52%] truncate"
            style={{
              color: stageColor ?? 'var(--muted)',
              backgroundColor: `${stageColor ?? '#9a9a94'}1f`,
            }}
            title={stageName}
          >
            {stageName}
          </span>
        )}
      </div>

      {(momento || responsavel) && (
        <div className="flex items-center gap-1 mt-1 flex-wrap">
          {momento && (
            <span
              className="text-[9px] font-semibold px-1.5 py-0.5 rounded-full"
              style={{ color: momento.cor, backgroundColor: `${momento.cor}1f` }}
              title={momento.descricao}
            >
              {momento.label}
            </span>
          )}
          {responsavel && responsavel !== 'CRM' && (
            <span
              className="text-[9px] font-semibold px-1.5 py-0.5 rounded-full"
              style={{
                color: corDoResponsavel ?? 'var(--muted)',
                backgroundColor: `${corDoResponsavel ?? '#9a9a94'}1f`,
              }}
              title={`Lead da ${responsavel}`}
            >
              {responsavel}
            </span>
          )}
        </div>
      )}
    </button>
  )
}

function SourceCard({
  sourceKey,
  leads,
  stageNameById,
  stageColorById,
  highlightedLeadId,
  onHighlightLead,
  onAdd,
}: {
  sourceKey: LeadSourceKey
  leads: LeadWithOwner[]
  stageNameById: Record<string, string>
  stageColorById: Record<string, string>
  highlightedLeadId: string | null
  onHighlightLead: (leadId: string) => void
  /** Abre a tabela de cadastro manual desta fonte. */
  onAdd?: () => void
}) {
  const def = LEAD_SOURCES[sourceKey]
  const color = SOURCE_COLORS[sourceKey]
  const [searchOpen, setSearchOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [collapsed, setCollapsed] = useState(false)

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return leads
    return leads.filter(
      (lead) =>
        lead.title?.toLowerCase().includes(q) ||
        lead.phone?.includes(q.replace(/\D/g, '')) ||
        lead.email?.toLowerCase().includes(q)
    )
  }, [leads, search])

  return (
    <div className="panel rounded-xl overflow-hidden flex-shrink-0">
      <div className="px-3 py-2.5 flex items-center gap-2">
        <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: color }} />
        <div className="min-w-0 flex-1">
          <p className="text-[12.5px] font-bold text-ink truncate leading-tight">{def.label}</p>
          <p className="text-[10px] text-muted">
            {leads.length} {leads.length === 1 ? 'lead' : 'leads'}
          </p>
        </div>
        <button
          type="button"
          onClick={() => { setSearchOpen((v) => !v); if (searchOpen) setSearch('') }}
          className={`btn-icon w-7 h-7 flex-shrink-0 ${searchOpen ? '!text-accent-2' : ''}`}
          title="Buscar nesta fonte"
        >
          {searchOpen ? <X size={13} weight="bold" /> : <MagnifyingGlass size={13} weight="bold" />}
        </button>
        <button
          type="button"
          onClick={() => setCollapsed((v) => !v)}
          className="btn-icon w-7 h-7 flex-shrink-0"
          title={collapsed ? 'Expandir' : 'Recolher'}
        >
          <CaretDown size={13} weight="bold" className={`transition-transform ${collapsed ? '-rotate-90' : ''}`} />
        </button>
      </div>

      {searchOpen && !collapsed && (
        <div className="px-2.5 pb-2">
          <input
            autoFocus
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Nome, telefone…"
            className="field !py-1.5 !text-[12px]"
          />
        </div>
      )}

      {!collapsed && (
        <>
          <div className="h-px hairline-x" />
          {/* max-h fixo é o que segura a promessa: o card não cresce com o número
              de leads — a lista rola por dentro. */}
          <div className="max-h-[260px] overflow-y-auto scrollbar-hide px-2 py-2 space-y-1.5">
            {visible.length === 0 ? (
              <div className="py-4 text-center">
                <p className="text-[11px] text-muted">
                  {search ? 'Nada encontrado.' : 'Nenhum lead ainda.'}
                </p>
              </div>
            ) : (
              visible.map((lead) => (
                <MiniCard
                  key={lead.id}
                  lead={lead}
                  stageName={lead.stage_id ? stageNameById[lead.stage_id] ?? null : null}
                  stageColor={lead.stage_id ? stageColorById[lead.stage_id] ?? null : null}
                  isHighlighted={highlightedLeadId === lead.id}
                  onClick={() => onHighlightLead(lead.id)}
                />
              ))
            )}
          </div>

          {/* Bloco de cadastro colado na borda de baixo do card, FORA da lista.
              A lista rola por dentro e pode ter 50 leads; o botão não pode
              depender de rolar até o fim pra aparecer. Fica sempre à vista, no
              rodapé, na cor da fonte. */}
          {onAdd && (
            <button
              type="button"
              onClick={onAdd}
              className="w-full flex items-center justify-center gap-1.5 px-3 py-2 border-t border-white/[0.07] bg-white/[0.02] hover:bg-white/[0.06] transition-colors text-[11.5px] font-bold uppercase tracking-wide"
              style={{ color }}
              title={`Cadastrar lead em ${def.label}`}
            >
              <Plus size={12} weight="bold" />
              Cadastrar leads
            </button>
          )}
        </>
      )}
    </div>
  )
}

/**
 * Fontes que aceitam cadastro à mão pelo Pipeline.
 *
 * Indicação só existe assim. Agenda e site normalmente chegam por formulário,
 * mas o time precisa registrar quem mandou os dados por mensagem ou cujo
 * formulário falhou — e aí a mensagem automática é opcional, decidida no
 * próprio formulário de cadastro.
 *
 * Fora da lista fica a planilha histórica (agenda_antigos): ela é importação,
 * não um canal por onde o lead entra hoje.
 */
const FONTES_MANUAIS: LeadSourceKey[] = ['agenda_ascensao', 'site_evento', 'indicacao']

export default function SourceRail({
  leads,
  stageNameById,
  stageColorById,
  highlightedLeadId,
  onHighlightLead,
}: SourceRailProps) {
  const { refetch } = useLeadsContext()
  const [cadastrando, setCadastrando] = useState<LeadSourceKey | null>(null)
  // Cadastro completo de UM lead (com Instagram, e-mail, observação e o
  // "adicionar campo"): a tabela cobre o dia a dia, este cobre o caso raro.
  const [cadastroCompleto, setCadastroCompleto] = useState<LeadSourceKey | null>(null)
  // Agrupa por fonte, mais recente em cima dentro de cada uma.
  const bySource = useMemo(() => {
    const groups: Record<string, LeadWithOwner[]> = {}
    for (const key of ACQUISITION_SOURCE_ORDER) groups[key] = []

    for (const lead of leads) {
      const source = sourceOf(lead)
      // O `groups[source]` é garantido pelo laço acima, mas o guarda fica: se
      // amanhã alguém alargar o sourceOf sem alargar os baldes, isso volta a
      // derrubar a tela inteira do Pipeline em vez de só omitir um card.
      if (source && groups[source]) groups[source].push(lead)
    }

    const timeOf = (lead: LeadWithOwner) =>
      new Date(lead.last_activity_at || lead.created_at || 0).getTime()
    for (const key of ACQUISITION_SOURCE_ORDER) groups[key].sort((a, b) => timeOf(b) - timeOf(a))

    return groups
  }, [leads])

  return (
    <div className="flex-shrink-0 w-full md:w-[240px] h-full min-h-0 flex flex-col">
      {/* Cabeçalho — o rótulo "Fonte:" que dá nome à coluna */}
      <div className="mb-3 px-2 pt-1">
        <h3 className="uppercase font-bold text-[12.5px] tracking-wider text-accent-2">Fonte:</h3>
        <p className="text-[11px] text-muted font-medium mt-0.5">De onde cada lead entrou</p>
        <div
          className="w-full h-[2px] rounded-full mt-3 mb-1"
          style={{ background: 'linear-gradient(90deg, var(--blue), transparent)' }}
        />
      </div>

      {/* glass-accent + a borda amarela à esquerda separam esta coluna das etapas */}
      <div className="glass glass-accent rounded-2xl border-l-2 border-l-accent/50 flex-1 min-h-0 overflow-y-auto scrollbar-hide p-2 space-y-2">
        {ACQUISITION_SOURCE_ORDER.map((key) => (
          <SourceCard
            key={key}
            sourceKey={key}
            leads={bySource[key] || []}
            stageNameById={stageNameById}
            stageColorById={stageColorById}
            highlightedLeadId={highlightedLeadId}
            onHighlightLead={onHighlightLead}
            onAdd={FONTES_MANUAIS.includes(key) ? () => setCadastrando(key) : undefined}
          />
        ))}
      </div>

      {cadastrando && (
        <TabelaCadastroManual
          source={cadastrando}
          onClose={() => setCadastrando(null)}
          onCreated={refetch}
          onCadastroCompleto={() => {
            setCadastroCompleto(cadastrando)
            setCadastrando(null)
          }}
        />
      )}

      {cadastroCompleto && (
        <NovoLeadManualModal
          source={cadastroCompleto}
          onClose={() => setCadastroCompleto(null)}
          onCreated={refetch}
        />
      )}
    </div>
  )
}
