'use client'

import { DotsThreeVertical, ArrowsClockwise, Plus } from '@phosphor-icons/react'

// ── Tag color mapping ──
const TAG_COLORS: Record<string, { bg: string; text: string }> = {
  WHATSAPP: { bg: 'bg-green-100', text: 'text-green-700' },
  FACEBOOK: { bg: 'bg-panel-2', text: 'text-accent-2' },
  'GOOGLE ADS': { bg: 'bg-yellow-100', text: 'text-yellow-700' },
  LINKEDIN: { bg: 'bg-panel-2', text: 'text-accent-2' },
  URGENTE: { bg: 'bg-red-100', text: 'text-red-600' },
  QUALIFICADO: { bg: 'bg-green-100', text: 'text-green-600' },
  PENDENTE: { bg: 'bg-orange-100', text: 'text-orange-600' },
  'SEM TAREFAS': { bg: 'bg-panel-2', text: 'text-muted' },
}

// ── Owner color mapping ──
const OWNER_COLORS: Record<string, string> = {
  RICARDO: 'text-orange-500',
  MARIANA: 'text-purple-600',
  LUCAS: 'text-accent-2',
  PEDRO: 'text-green-600',
}

// ── Types ──
interface MockLead {
  id: string
  owner: string
  time: string
  title: string
  description: string
  tags: string[]
}

interface MockStage {
  id: string
  name: string
  leadCount: number
  value: string
  barColor: string
  barWidth: string
  leads: MockLead[]
}

// ── Mock Data (exatamente como na screenshot) ──
const MOCK_STAGES: MockStage[] = [
  {
    id: '1', name: 'ENTRADA', leadCount: 8, value: 'R$ 8.200',
    barColor: 'bg-accent', barWidth: 'w-1/3',
    leads: [
      { id: 'l1', owner: 'RICARDO', time: '12:45', title: 'Condomínio Solar', description: 'Interesse em manutenção corretiva de 4 máquinas.', tags: ['WHATSAPP'] },
      { id: 'l2', owner: 'MARIANA', time: 'Hoje', title: 'Hotel Fazenda Rio', description: 'Troca de frota industrial - 10 unidades.', tags: ['FACEBOOK', 'URGENTE'] },
    ],
  },
  {
    id: '2', name: 'QUALIFICAÇÃO', leadCount: 5, value: 'R$ 15.000',
    barColor: 'bg-accent', barWidth: 'w-1/4',
    leads: [
      { id: 'l3', owner: 'MARIANA', time: '02/02/2026', title: 'Lavanderia Express', description: 'Precisa de 3 máquinas industriais para nova filial.', tags: ['WHATSAPP', 'QUALIFICADO'] },
      { id: 'l4', owner: 'RICARDO', time: 'Ontem', title: 'CleanPro Serviços', description: 'Orçamento para linha completa de lavanderia.', tags: ['GOOGLE ADS'] },
    ],
  },
  {
    id: '3', name: 'EM DESENVOLVIMENTO', leadCount: 13, value: 'R$ 12.400',
    barColor: 'bg-accent', barWidth: 'w-2/3',
    leads: [
      { id: 'l5', owner: 'MARIANA', time: '04/02/2026', title: 'Agile Administradora', description: 'Aluguel de máquina de lavar ou venda direta para condomínio.', tags: ['GOOGLE ADS', 'PEDRO'] },
      { id: 'l6', owner: 'MARIANA', time: '03/02/2026', title: 'Caio Vinícius', description: 'Lavadora e secadora industrial', tags: ['FACEBOOK', 'PENDENTE'] },
      { id: 'l7', owner: 'MARIANA', time: 'Ontem 12:28', title: 'Itamar Ferreira Jr', description: 'Fui funcionário de uma empresa privada durante 30 anos...', tags: ['SEM TAREFAS'] },
    ],
  },
  {
    id: '4', name: 'PROPOSTA', leadCount: 3, value: 'R$ 42.000',
    barColor: 'bg-orange-400', barWidth: 'w-1/5',
    leads: [
      { id: 'l8', owner: 'LUCAS', time: '2 dias', title: 'Maternidade Vida', description: 'Proposta enviada para esterilizadores de alta pressão.', tags: ['LINKEDIN'] },
      { id: 'l9', owner: 'MARIANA', time: 'Ontem', title: 'Rede Smart Fit', description: 'Aguardando assinatura do contrato de leasing.', tags: ['QUALIFICADO'] },
    ],
  },
  {
    id: '5', name: 'NEGOCIAÇÃO', leadCount: 2, value: 'R$ 18.500',
    barColor: 'bg-orange-400', barWidth: 'w-1/6',
    leads: [],
  },
]

// ── Lead Card Component ──
function LeadCard({ lead }: { lead: MockLead }) {
  const ownerColor = OWNER_COLORS[lead.owner] || 'text-muted'

  return (
    <div className="bg-panel rounded-xl p-4 shadow-sm border border-line hover:shadow-md transition-shadow cursor-pointer">
      {/* Owner + Time */}
      <div className="flex items-center justify-between mb-1.5">
        <span className={`text-xs font-bold uppercase ${ownerColor}`}>
          {lead.owner}
        </span>
        <span className="text-xs text-muted">{lead.time}</span>
      </div>

      {/* Title */}
      <h4 className="font-semibold text-ink text-sm mb-1 font-display">{lead.title}</h4>

      {/* Description */}
      <p className="text-xs text-muted mb-3 line-clamp-2">{lead.description}</p>

      {/* Tags */}
      <div className="flex flex-wrap gap-1.5">
        {lead.tags.map((tag) => {
          const colors = TAG_COLORS[tag] || { bg: 'bg-panel-2', text: 'text-muted' }
          return (
            <span
              key={tag}
              className={`px-2 py-0.5 rounded text-[10px] font-bold uppercase ${colors.bg} ${colors.text}`}
            >
              {tag}
            </span>
          )
        })}
      </div>
    </div>
  )
}

// ── Main Pipeline Board ──
export default function PipelineBoardMock() {
  return (
    <div className="flex flex-col h-[calc(100vh-90px)] bg-void relative">
      {/* Kanban Board */}
      <div className="flex-1 overflow-x-auto px-6 py-4">
        <div className="flex gap-4 h-full min-w-max">
          {MOCK_STAGES.map((stage) => (
            <div key={stage.id} className="w-[260px] flex flex-col flex-shrink-0">
              {/* Stage Header */}
              <div className="mb-3">
                <div className="flex items-center justify-between mb-1">
                  <span className="text-xs font-bold text-muted uppercase tracking-wide font-display">
                    {stage.name}
                  </span>
                  <button className="text-muted hover:text-muted">
                    <DotsThreeVertical size={16} weight="bold" />
                  </button>
                </div>
                <div className="flex items-center gap-1.5 mb-2">
                  <span className="text-lg font-bold text-ink font-display">
                    {String(stage.leadCount).padStart(2, '0')}
                  </span>
                  <span className="text-xs text-muted">
                    leads &bull; {stage.value}
                  </span>
                </div>
                {/* Progress Bar */}
                <div className="w-full h-1 bg-panel-2 rounded-full overflow-hidden">
                  <div className={`h-full rounded-full ${stage.barColor} ${stage.barWidth}`} />
                </div>
              </div>

              {/* Lead Cards */}
              <div className="flex-1 space-y-3 overflow-y-auto pr-1">
                {stage.leads.length === 0 ? (
                  <div className="text-center py-8 text-muted text-xs">
                    Sem leads
                  </div>
                ) : (
                  stage.leads.map((lead) => (
                    <LeadCard key={lead.id} lead={lead} />
                  ))
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* FAB Buttons */}
      <div className="fixed bottom-6 right-6 flex flex-col gap-3 z-50">
        <button className="w-10 h-10 bg-panel border border-line rounded-full shadow-lg flex items-center justify-center text-muted hover:bg-void transition-colors">
          <ArrowsClockwise size={16} />
        </button>
        <button className="w-12 h-12 bg-accent rounded-full shadow-lg flex items-center justify-center text-white hover:bg-accent transition-colors">
          <Plus size={24} weight="bold" />
        </button>
      </div>
    </div>
  )
}
