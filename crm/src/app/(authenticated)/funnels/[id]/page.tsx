'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
import { useParams, useRouter } from 'next/navigation'
import { ArrowLeft, FloppyDisk, CheckCircle, ChartBar } from '@phosphor-icons/react'
import MetricasDoFluxo from '@/components/Funnels/MetricasDoFluxo'
import type { Edge } from '@xyflow/react'
import FunnelEditor, { type FunnelBlockData, type StageOption } from '@/components/Funnels/FunnelEditor'
import { useAuth, usePipeline } from '@/hooks'

type FlowNode = {
  id: string
  type: string
  position: { x: number; y: number }
  data: FunnelBlockData
}

const BRANCH_LABEL: Record<string, string> = { yes: 'Sim', no: 'Não' }
const BRANCH_COLOR: Record<string, string> = { yes: '#10b981', no: '#ef4444', default: '#94a3b8' }

export default function FunnelEditorPage() {
  const params = useParams()
  const router = useRouter()
  const funnelId = params.id as string

  const [loading, setLoading] = useState(true)
  const [name, setName] = useState('')
  const [isActive, setIsActive] = useState(false)
  const [trigger, setTrigger] = useState('novo_recuperacao')
  const [nodes, setNodes] = useState<FlowNode[]>([])
  const [edges, setEdges] = useState<Edge[]>([])
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [verMetricas, setVerMetricas] = useState(false)

  // Etapas do pipeline — alimentam o seletor do bloco "Mover de etapa".
  const { organizationId } = useAuth()
  const { stages } = usePipeline(organizationId || '')
  const stageOptions: StageOption[] = stages.map((s) => ({ id: s.id, name: s.name }))

  const flowRef = useRef<{ nodes: FlowNode[]; edges: Edge[] }>({ nodes: [], edges: [] })
  const saveTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const stateRef = useRef({ name, isActive, trigger })
  stateRef.current = { name, isActive, trigger }

  useEffect(() => {
    const load = async () => {
      const res = await fetch(`/api/funnels/${funnelId}`)
      if (!res.ok) {
        setLoading(false)
        return
      }
      const { data } = await res.json()
      setName(data.name)
      setIsActive(!!data.is_active)
      setTrigger(data.trigger)

      const flowNodes: FlowNode[] = data.blocks.map((b: any) => ({
        id: b.id,
        type: b.type,
        position: { x: Number(b.positionX) || 0, y: Number(b.positionY) || 0 },
        data: {
          blockType: b.type,
          config: b.type === 'trigger' ? { ...(b.config || {}), trigger: (b.config?.trigger ?? data.trigger) } : (b.config || {}),
        },
      }))

      const flowEdges: Edge[] = data.connections.map((c: any) => {
        const branch = c.branch === 'yes' || c.branch === 'no' ? c.branch : 'default'
        return {
          id: c.id,
          source: c.sourceBlockId,
          target: c.targetBlockId,
          sourceHandle: branch === 'default' ? undefined : branch,
          label: BRANCH_LABEL[branch],
          style: { stroke: BRANCH_COLOR[branch] },
          labelStyle: { fill: BRANCH_COLOR[branch], fontWeight: 700, fontSize: 11 },
        }
      })

      setNodes(flowNodes)
      setEdges(flowEdges)
      flowRef.current = { nodes: flowNodes, edges: flowEdges }
      setLoading(false)
    }
    load()
  }, [funnelId])

  const handleSave = useCallback(async () => {
    setSaving(true)
    setSaved(false)
    try {
      const { nodes: currentNodes, edges: currentEdges } = flowRef.current
      const { name: currentName, isActive: currentIsActive, trigger: currentTrigger } = stateRef.current

      const blocks = currentNodes.map((n) => ({
        id: n.id,
        type: n.data.blockType,
        config: n.data.config || {},
        position: n.position,
      }))

      const connections = currentEdges.map((e) => ({
        source: e.source,
        target: e.target,
        branch: e.sourceHandle === 'yes' || e.sourceHandle === 'no' ? e.sourceHandle : 'default',
      }))

      const res = await fetch(`/api/funnels/${funnelId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: currentName, isActive: currentIsActive, trigger: currentTrigger, blocks, connections }),
      })

      if (res.ok) {
        setSaved(true)
        setTimeout(() => setSaved(false), 2000)
      }
    } finally {
      setSaving(false)
    }
  }, [funnelId])

  const handleFlowChange = useCallback((n: FlowNode[], e: Edge[]) => {
    flowRef.current = { nodes: n, edges: e }

    if (saveTimeoutRef.current) clearTimeout(saveTimeoutRef.current)
    saveTimeoutRef.current = setTimeout(() => {
      handleSave()
    }, 1000)
  }, [handleSave])

  if (loading) {
    return (
      <div className="h-full flex items-center justify-center bg-panel">
        <div className="w-6 h-6 border-2 border-line border-t-blue-500 rounded-full animate-spin" />
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col bg-panel">
      <div className="sticky top-0 z-10 bg-panel border-b border-line px-6 py-3 flex items-center justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0">
          <button onClick={() => router.push('/funnels')} className="text-muted hover:text-muted transition-colors">
            <ArrowLeft size={18} weight="bold" />
          </button>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="text-base font-bold text-ink border-none focus:outline-none focus:ring-0 bg-transparent min-w-0"
          />
        </div>

        <div className="flex items-center gap-3 shrink-0">
          <label className="flex items-center gap-2 cursor-pointer">
            <button
              onClick={() => { if (trigger !== 'geracaowhatsapp') setIsActive((v) => !v) }}
              disabled={trigger === 'geracaowhatsapp'}
              title={trigger === 'geracaowhatsapp' ? 'Fluxo padrão: não pode ser desativado' : undefined}
              className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${isActive ? 'bg-emerald-500' : 'bg-panel-2'} ${trigger === 'geracaowhatsapp' ? 'cursor-not-allowed opacity-80' : ''}`}
            >
              <span className={`inline-block h-4 w-4 transform rounded-full bg-panel transition-transform ${isActive ? 'translate-x-4.5' : 'translate-x-0.5'}`} />
            </button>
            <span className={`text-xs font-semibold ${isActive ? 'text-emerald-600' : 'text-muted'}`}>
              {isActive ? 'Ativo' : 'Inativo'}
            </span>
            {trigger === 'geracaowhatsapp' && (
              <span className="text-[10px] text-muted">🔒 padrão</span>
            )}
          </label>

          {/* Métricas do fluxo: envios e, principalmente, quem respondeu cada
              versão da mensagem no teste A/B/C. */}
          <button
            onClick={() => setVerMetricas(true)}
            className="flex items-center gap-1.5 text-sm font-semibold px-3 py-1.5 rounded-lg border border-line text-ink hover:bg-white/[0.06] transition-colors"
          >
            <ChartBar size={16} weight="bold" />
            Métricas
          </button>

          <button
            onClick={handleSave}
            disabled={saving}
            className="flex items-center gap-1.5 bg-accent hover:bg-accent-2 disabled:opacity-50 text-white text-sm font-semibold px-3 py-1.5 rounded-lg transition-colors"
          >
            {saved ? <CheckCircle size={16} weight="bold" /> : <FloppyDisk size={16} weight="bold" />}
            {saving ? 'Salvando...' : saved ? 'Salvo!' : 'Salvar'}
          </button>
        </div>
      </div>

      <div className="flex-1 relative">
        <FunnelEditor initialNodes={nodes as any} initialEdges={edges} stages={stageOptions} funnelId={funnelId} onChange={handleFlowChange as any} />

        {verMetricas && (
          <MetricasDoFluxo
            funnelId={funnelId}
            rotuloDoBloco={(blockId) => {
              const bloco = nodes.find((n: any) => n.id === blockId) as any
              return bloco?.data?.label || bloco?.data?.config?.label || 'Mensagem'
            }}
            onClose={() => setVerMetricas(false)}
          />
        )}
      </div>
    </div>
  )
}
