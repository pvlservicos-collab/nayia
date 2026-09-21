'use client'

import { ReactFlow, ReactFlowProvider, Background, Handle, Position, type NodeProps } from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import { ChartLineUp, Gift, Database, WhatsappLogo } from '@phosphor-icons/react'
import GlassCard, { SectionHeader } from './GlassCard'

interface FlowNodeData extends Record<string, unknown> {
  label: string
  sublabel?: string
  category: string
  color: string
  icon: React.ComponentType<any>
  hasTarget?: boolean
  hasSource?: boolean
}

function FlowNode({ data }: NodeProps) {
  const d = data as unknown as FlowNodeData
  const Icon = d.icon
  return (
    <div
      className="glass rounded-2xl px-4 py-3 w-[220px]"
      style={{
        // A cor da categoria entra só como fio + lavagem por cima do vidro — o
        // corpo do nó continua sendo a superfície cinza translúcida do sistema.
        borderColor: `${d.color}66`,
        boxShadow: `var(--glass-lift), 0 0 0 1px ${d.color}22, 0 0 24px -12px ${d.color}88`,
        backgroundColor: `${d.color}12`,
      }}
    >
      {d.hasTarget && <Handle type="target" position={Position.Left} style={{ background: d.color, border: 'none', width: 8, height: 8 }} />}
      <div className="flex items-center gap-1.5 mb-1.5">
        <Icon size={13} weight="bold" style={{ color: d.color }} />
        <span className="text-[9px] font-bold uppercase tracking-wider" style={{ color: d.color }}>{d.category}</span>
      </div>
      <p className="text-[13px] font-bold text-ink leading-tight">{d.label}</p>
      {d.sublabel && <p className="text-[11px] text-muted mt-0.5 leading-tight">{d.sublabel}</p>}
      {d.hasSource && <Handle type="source" position={Position.Right} style={{ background: d.color, border: 'none', width: 8, height: 8 }} />}
    </div>
  )
}

const nodeTypes = { flowNode: FlowNode }

const COLOR_ORGANIC = '#3987e5'
const COLOR_MAGNET_1 = '#c98500'
const COLOR_MAGNET_2 = '#d95926'
const COLOR_CRM = '#f2c744'
const COLOR_WHATSAPP = '#199e70'

const nodes = [
  {
    id: 'organic',
    type: 'flowNode',
    position: { x: 0, y: 0 },
    data: { label: 'Tráfego Orgânico', sublabel: 'FORM · Site · Indicações', category: 'Canal orgânico', color: COLOR_ORGANIC, icon: ChartLineUp, hasSource: true },
  },
  {
    id: 'magnet-agenda',
    type: 'flowNode',
    position: { x: 0, y: 130 },
    data: { label: 'Minha Agenda em Ascensão', sublabel: 'Isca de conteúdo', category: 'Isca (lead magnet)', color: COLOR_MAGNET_1, icon: Gift, hasSource: true },
  },
  {
    id: 'magnet-evento',
    type: 'flowNode',
    position: { x: 0, y: 260 },
    data: { label: 'Evento Ascensão', sublabel: 'Isca de conteúdo', category: 'Isca (lead magnet)', color: COLOR_MAGNET_2, icon: Gift, hasSource: true },
  },
  {
    id: 'crm',
    type: 'flowNode',
    position: { x: 340, y: 130 },
    data: { label: 'TitaCRM', sublabel: 'Organiza, qualifica e distribui', category: 'CRM', color: COLOR_CRM, icon: Database, hasTarget: true, hasSource: true },
  },
  {
    id: 'whatsapp',
    type: 'flowNode',
    position: { x: 660, y: 130 },
    data: { label: 'WhatsApp', sublabel: 'Follow-up humano + IA', category: 'Canal de conversa', color: COLOR_WHATSAPP, icon: WhatsappLogo, hasTarget: true },
  },
]

const edges = [
  { id: 'e-organic-crm', source: 'organic', target: 'crm', style: { stroke: COLOR_ORGANIC, strokeWidth: 2 }, animated: true },
  { id: 'e-agenda-crm', source: 'magnet-agenda', target: 'crm', style: { stroke: COLOR_MAGNET_1, strokeWidth: 2 }, animated: true },
  { id: 'e-evento-crm', source: 'magnet-evento', target: 'crm', style: { stroke: COLOR_MAGNET_2, strokeWidth: 2 }, animated: true },
  { id: 'e-crm-whatsapp', source: 'crm', target: 'whatsapp', style: { stroke: COLOR_CRM, strokeWidth: 2 }, animated: true },
]

const LEGEND = [
  { label: 'Canal orgânico', color: COLOR_ORGANIC },
  { label: 'Isca — Minha Agenda em Ascensão', color: COLOR_MAGNET_1 },
  { label: 'Isca — Evento Ascensão', color: COLOR_MAGNET_2 },
  { label: 'CRM', color: COLOR_CRM },
  { label: 'WhatsApp (follow-up)', color: COLOR_WHATSAPP },
]

export default function BusinessFlowDiagram() {
  return (
    <GlassCard className="p-5">
      <SectionHeader icon={<ChartLineUp size={16} weight="bold" />} title="Como os leads chegam até você" subtitle="Visão geral do funil — da origem ao WhatsApp" />

      <div className="glass-sunken h-[340px] rounded-2xl overflow-hidden">
        <ReactFlowProvider>
          <ReactFlow
            nodes={nodes}
            edges={edges}
            nodeTypes={nodeTypes}
            fitView
            fitViewOptions={{ padding: 0.25 }}
            nodesDraggable={false}
            nodesConnectable={false}
            elementsSelectable={false}
            zoomOnScroll={false}
            panOnScroll
            proOptions={{ hideAttribution: true }}
          >
            <Background gap={18} size={1} color="rgba(255,255,255,0.08)" />
          </ReactFlow>
        </ReactFlowProvider>
      </div>

      <div className="h-px hairline-x mt-3" />

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 pt-3">
        {LEGEND.map((item) => (
          <span key={item.label} className="flex items-center gap-1.5 text-[11px] text-muted">
            <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: item.color }} />
            {item.label}
          </span>
        ))}
      </div>
    </GlassCard>
  )
}
