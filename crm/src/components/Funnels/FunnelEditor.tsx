'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  ReactFlow,
  ReactFlowProvider,
  Background,
  Controls,
  addEdge,
  applyNodeChanges,
  applyEdgeChanges,
  Handle,
  Position,
  type Node,
  type Edge,
  type Connection,
  type NodeChange,
  type EdgeChange,
  type NodeProps,
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import {
  Lightning,
  WhatsappLogo,
  PlayCircle,
  ChatCircleDots,
  HourglassSimple,
  GitBranch,
  FlagCheckered,
  ArrowsLeftRight,
  Plus,
  Trash,
  X,
} from '@phosphor-icons/react'

export interface FunnelBlockData {
  blockType: 'trigger' | 'message' | 'wait' | 'condition' | 'end' | 'move_stage'
  config: Record<string, any>
  [key: string]: unknown
}

type FlowNode = Node<FunnelBlockData>

/** Só o que o bloco "Mover de etapa" precisa saber sobre uma etapa. */
export interface StageOption {
  id: string
  name: string
}

const TRIGGER_LABELS: Record<string, string> = {
  novo_pago: 'Novo Pago',
  novo_recuperacao: 'Novo Recuperação',
  lead_site_evento: 'Lead novo — Site Evento',
  lead_agenda_ascensao: 'Lead novo — Agenda Ascensão',
}

const CONDITION_TYPE_LABELS: Record<string, string> = {
  respondeu: 'Respondeu mensagem',
  clique_pagina: 'Clicou no link / viu a página',
  pagamento: 'Pagamento confirmado',
  // A Agenda só manda área/aumento/investimento quando o formulário do fim é
  // concluído — ter esses campos É a confirmação de cadastro. Usado pra não
  // mandar mensagem de retomada pra quem já se cadastrou.
  formulario_agenda: 'Preencheu o formulário do fim da agenda',
}

const TRIGGER_WEBHOOKS: Record<string, string> = {
  novo_pago: '/api/webhooks/recuperacao (pago)',
  novo_recuperacao: '/api/webhooks/recuperacao',
  lead_site_evento: '/api/ingest/leads/site_evento',
  lead_agenda_ascensao: '/api/ingest/leads/agenda_ascensao',
}

const CONDITION_WEBHOOKS: Record<string, string> = {
  pagamento: '/api/webhooks/recuperacao (confirmação)',
}

// ── Nós do canvas ───────────────────────────────────────────────────────────
//
// O visual é o do ManyChat, a pedido: cartão branco sobre fundo cinza claro,
// cabeçalho com o canal em cima do nome do bloco, faixa de números em azul,
// e o conteúdo da mensagem numa "bolha" cinza igual à do WhatsApp.
//
// O canvas mantém a aparência clara mesmo com o CRM no tema escuro. É uma
// prancheta: as cores aqui são as do fluxo (verde = gatilho, azul = número,
// cinza = mensagem) e precisam significar a mesma coisa nos dois temas.

/** Paleta do canvas — fixa, independente do tema do resto do app. */
const C = {
  cartao: '#FFFFFF',
  borda: '#EAECF0',
  texto: '#101828',
  textoFraco: '#667085',
  bolha: '#F2F4F7',
  bolhaTexto: '#344054',
  numero: '#2E90FA',
  fio: '#98A2B3',
  verde: '#ECFDF3',
  verdeBorda: '#D1FADF',
}

const SOMBRA = '0 1px 3px rgba(16,24,40,.10), 0 8px 24px -8px rgba(16,24,40,.10)'

/** Bolinha de conexão — igual nas duas pontas, como no ManyChat. */
function Conector({ tipo, id, style }: { tipo: 'source' | 'target'; id?: string; style?: React.CSSProperties }) {
  return (
    <Handle
      type={tipo}
      id={id}
      position={tipo === 'source' ? Position.Right : Position.Left}
      style={{
        width: 11,
        height: 11,
        background: C.fio,
        border: '2px solid #fff',
        boxShadow: '0 0 0 1px ' + C.fio,
        ...style,
      }}
    />
  )
}

function Cartao({ selected, largura = 288, children }: { selected?: boolean; largura?: number; children: React.ReactNode }) {
  return (
    <div
      style={{
        width: largura,
        background: C.cartao,
        borderRadius: 16,
        boxShadow: selected ? '0 0 0 2px ' + C.numero + ', ' + SOMBRA : SOMBRA,
      }}
    >
      {children}
    </div>
  )
}

/** Cabeçalho: ícone redondo + canal em cima, nome do bloco embaixo. */
function Cabecalho({ icone, canal, nome }: { icone: React.ReactNode; canal: string; nome: string }) {
  return (
    <div className="flex items-center gap-2.5 px-4 pt-3.5 pb-1">
      {/* Selo do canal. O layout é o do ManyChat (print de um fluxo de
          Instagram), mas o canal daqui é o WhatsApp — manter o degradê roxo do
          Instagram deixaria o cartão bonito e mentindo sobre por onde a
          mensagem sai. */}
      <div
        className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0"
        style={{ background: '#25D366' }}
      >
        {icone}
      </div>
      <div className="min-w-0">
        <p style={{ color: C.textoFraco }} className="text-[11px] leading-none">{canal}</p>
        <p style={{ color: C.texto }} className="text-[15px] font-semibold leading-tight truncate">{nome}</p>
      </div>
    </div>
  )
}

/**
 * A faixa de números do ManyChat.
 *
 * Só entram métricas que o CRM mede de verdade. "Aberto" (recibo de leitura)
 * ficou de fora porque ninguém registra isso aqui ainda — a coluna existiria
 * com número inventado, e quem olha decide em cima dela.
 */
function Numeros({ stats }: { stats?: EstatisticasBloco }) {
  const enviado = stats?.enviado ?? 0
  const pct = (n: number) => (enviado > 0 ? ((n / enviado) * 100).toFixed(1).replace('.', ',') + '%' : '—')

  const colunas = [
    { valor: String(enviado), rotulo: 'Enviado' },
    { valor: pct(stats?.entregue ?? 0), rotulo: 'Entregue' },
    { valor: pct(stats?.respondeu ?? 0), rotulo: 'Respondeu' },
    { valor: pct(stats?.clicou ?? 0), rotulo: 'Clicado' },
  ]

  return (
    <div className="flex items-start justify-between px-4 pt-1.5 pb-2.5">
      {colunas.map((c) => (
        <div key={c.rotulo} className="text-center">
          <p style={{ color: C.numero }} className="text-[17px] font-normal leading-tight tabular-nums">{c.valor}</p>
          <p style={{ color: C.textoFraco }} className="text-[11px] leading-tight">{c.rotulo}</p>
        </div>
      ))}
    </div>
  )
}

/** Rodapé com a saída do bloco ("Próximo Passo", "Então"). */
function Saida({ rotulo, id, top }: { rotulo: string; id?: string; top?: string }) {
  return (
    <div className="relative px-4 pb-3 pt-1">
      <p style={{ color: C.textoFraco }} className="text-[12px] text-right">{rotulo}</p>
      <Conector tipo="source" id={id} style={top ? { top } : undefined} />
    </div>
  )
}

function IconeCanal() {
  return <WhatsappLogo size={16} weight="fill" color="#fff" />
}

export interface EstatisticasBloco {
  enviado: number
  entregue: number
  respondeu: number
  clicou: number
}

function statsDo(data: FunnelBlockData): EstatisticasBloco | undefined {
  return (data as any).stats as EstatisticasBloco | undefined
}

function TriggerNode({ data, selected }: NodeProps<FlowNode>) {
  const config = data.config || {}
  return (
    <Cartao selected={selected} largura={310}>
      <div className="flex items-center gap-2.5 px-4 pt-4 pb-3">
        <Lightning size={20} weight="fill" color={C.texto} />
        <p style={{ color: C.texto }} className="text-[16px] font-semibold">Quando…</p>
      </div>

      <div className="px-3 pb-2">
        <div
          className="flex items-center gap-2.5 rounded-xl px-3 py-2.5"
          style={{ background: C.verde, border: '1px solid ' + C.verdeBorda }}
        >
          <div
            className="w-6 h-6 rounded-full flex items-center justify-center flex-shrink-0"
            style={{ background: '#25D366' }}
          >
            <IconeCanal />
          </div>
          <div className="min-w-0">
            <p style={{ color: C.texto }} className="text-[13px] font-medium leading-tight">
              {TRIGGER_LABELS[config.trigger] || 'Selecione o gatilho'}
            </p>
            <p style={{ color: C.textoFraco }} className="text-[11px] leading-tight">
              {TRIGGER_WEBHOOKS[config.trigger] ? 'Dispara sozinho quando o lead entra' : 'Escolha o que inicia este fluxo'}
            </p>
          </div>
        </div>
      </div>

      <Saida rotulo="Então" />
    </Cartao>
  )
}

function MessageNode({ data, selected }: NodeProps<FlowNode>) {
  const config = data.config || {}
  const texto = (config.text || '').trim()
  return (
    <Cartao selected={selected}>
      <Conector tipo="target" />
      <Cabecalho icone={<IconeCanal />} canal="WhatsApp" nome={config.titulo || 'Enviar Mensagem'} />
      <Numeros stats={statsDo(data)} />

      <div className="px-3 pb-1">
        <div className="rounded-xl px-3.5 py-3" style={{ background: C.bolha }}>
          {texto ? (
            <p style={{ color: C.bolhaTexto }} className="text-[13px] leading-[1.55] whitespace-pre-wrap break-words line-clamp-[12]">
              {texto}
            </p>
          ) : (
            <p style={{ color: C.textoFraco }} className="text-[13px] italic">Sem texto definido</p>
          )}
        </div>
      </div>

      {config.trackableUrl && (
        <div className="px-3 pb-1">
          <div className="rounded-lg px-3 py-2 text-[12px] truncate" style={{ background: '#fff', border: '1px solid ' + C.borda, color: C.numero }}>
            🔗 {config.trackableUrl}
          </div>
        </div>
      )}

      <Saida rotulo="Próximo Passo" />
    </Cartao>
  )
}

function WaitNode({ data, selected }: NodeProps<FlowNode>) {
  const config = data.config || {}
  const unidades: Record<string, string> = { seconds: 'segundos', minutes: 'minutos', hours: 'horas', days: 'dias' }
  return (
    <Cartao selected={selected} largura={260}>
      <Conector tipo="target" />
      <div className="flex items-center gap-2.5 px-4 pt-3.5 pb-1">
        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: '#FFFAEB' }}>
          <HourglassSimple size={15} weight="fill" color="#F79009" />
        </div>
        <div>
          <p style={{ color: C.textoFraco }} className="text-[11px] leading-none">Espera</p>
          <p style={{ color: C.texto }} className="text-[15px] font-semibold leading-tight">Antes de continuar</p>
        </div>
      </div>
      <div className="px-3 pb-1 pt-1.5">
        <div className="rounded-xl px-3.5 py-2.5 text-[13px]" style={{ background: C.bolha, color: C.bolhaTexto }}>
          {config.value ?? 0} {unidades[config.unit] || 'minutos'}
        </div>
      </div>
      <Saida rotulo="Próximo Passo" />
    </Cartao>
  )
}

function ConditionNode({ data, selected }: NodeProps<FlowNode>) {
  const config = data.config || {}
  const unidades: Record<string, string> = { minutes: 'minutos', hours: 'horas', days: 'dias' }
  const stats = statsDo(data)
  return (
    <Cartao selected={selected}>
      <Conector tipo="target" />
      <div className="flex items-center gap-2.5 px-4 pt-3.5 pb-1">
        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: '#FFF4ED' }}>
          <GitBranch size={15} weight="fill" color="#EF6820" />
        </div>
        <div>
          <p style={{ color: C.textoFraco }} className="text-[11px] leading-none">Condição</p>
          <p style={{ color: C.texto }} className="text-[15px] font-semibold leading-tight">
            {CONDITION_TYPE_LABELS[config.conditionType] || CONDITION_TYPE_LABELS.respondeu}
          </p>
        </div>
      </div>
      <Numeros stats={stats} />

      <div className="px-3 pb-1">
        <div className="rounded-xl px-3.5 py-2.5 text-[13px]" style={{ background: C.bolha, color: C.bolhaTexto }}>
          Aguarda até {config.value ?? 0} {unidades[config.unit] || 'minutos'}
        </div>
      </div>

      <div className="relative px-4 pb-3 pt-2 space-y-2">
        <div className="relative">
          <p className="text-[12px] text-right" style={{ color: '#12B76A' }}>Respondeu</p>
          <Conector tipo="source" id="yes" style={{ top: '50%' }} />
        </div>
        <div className="relative">
          <p className="text-[12px] text-right" style={{ color: '#F04438' }}>Não respondeu</p>
          <Conector tipo="source" id="no" style={{ top: '84%' }} />
        </div>
      </div>
    </Cartao>
  )
}

function MoveStageNode({ data, selected }: NodeProps<FlowNode>) {
  const config = data.config || {}
  return (
    <Cartao selected={selected} largura={260}>
      <Conector tipo="target" />
      <div className="flex items-center gap-2.5 px-4 pt-3.5 pb-1">
        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: '#F0FDF9' }}>
          <ArrowsLeftRight size={15} weight="fill" color="#15B79E" />
        </div>
        <div>
          <p style={{ color: C.textoFraco }} className="text-[11px] leading-none">Pipeline</p>
          <p style={{ color: C.texto }} className="text-[15px] font-semibold leading-tight">Mover de etapa</p>
        </div>
      </div>
      <div className="px-3 pb-1 pt-1.5">
        <div className="rounded-xl px-3.5 py-2.5 text-[13px]" style={{ background: C.bolha, color: C.bolhaTexto }}>
          {config.stageName ? '→ ' + config.stageName : 'Selecione a etapa'}
        </div>
      </div>
      <Saida rotulo="Próximo Passo" />
    </Cartao>
  )
}

function EndNode({ selected }: NodeProps<FlowNode>) {
  return (
    <Cartao selected={selected} largura={200}>
      <Conector tipo="target" />
      <div className="flex items-center gap-2.5 px-4 py-3.5">
        <div className="w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: C.bolha }}>
          <FlagCheckered size={15} weight="fill" color={C.textoFraco} />
        </div>
        <p style={{ color: C.texto }} className="text-[15px] font-semibold">Fim do fluxo</p>
      </div>
    </Cartao>
  )
}

const nodeTypes = {
  trigger: TriggerNode,
  message: MessageNode,
  wait: WaitNode,
  condition: ConditionNode,
  move_stage: MoveStageNode,
  end: EndNode,
}

// ── Block Editor Panel ──────────────────────────────────────────────────────

function BlockEditorPanel({ node, stages, onChange, onDelete, onClose }: {
  node: FlowNode
  stages: StageOption[]
  onChange: (config: Record<string, any>) => void
  onDelete: () => void
  onClose: () => void
}) {
  const config = node.data.config || {}

  return (
    <div className="absolute top-0 right-0 h-full w-80 bg-panel border-l border-line shadow-xl z-20 flex flex-col">
      <div className="flex items-center justify-between px-4 py-3 border-b border-line">
        <h3 className="text-sm font-bold text-ink">
          {node.data.blockType === 'trigger' && 'Gatilho'}
          {node.data.blockType === 'message' && 'Mensagem'}
          {node.data.blockType === 'wait' && 'Espera Minha Mensagem'}
          {node.data.blockType === 'condition' && 'Espera Mensagem Dele'}
          {node.data.blockType === 'move_stage' && 'Mover de etapa'}
          {node.data.blockType === 'end' && 'Fim'}
        </h3>
        <button onClick={onClose} className="text-muted hover:text-muted">
          <X size={18} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {node.data.blockType === 'trigger' && (
          <div>
            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Gatilho</label>
            <select
              value={config.trigger || 'novo_recuperacao'}
              onChange={(e) => onChange({ ...config, trigger: e.target.value })}
              className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            >
              {Object.entries(TRIGGER_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </div>
        )}

        {node.data.blockType === 'message' && (
          <>
            {/*
              Teste A/B/C: cada lead recebe UMA das versões, sorteada, e o CRM
              guarda qual foi. Em "Métricas" dá pra ver qual delas fez mais
              gente responder. Sem versões, vale o texto único abaixo.
            */}
            <TesteDeMensagens config={config} onChange={onChange} />

            {(!Array.isArray(config.variantes) || config.variantes.length === 0) && (
              <div>
                <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Texto da mensagem</label>
                <textarea
                  value={config.text || ''}
                  onChange={(e) => onChange({ ...config, text: e.target.value })}
                  rows={6}
                  placeholder="Ex: Olá {nome}, tudo bem?"
                  className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent resize-none"
                />
                <p className="text-[11px] text-muted mt-1">
                  Use <code className="bg-panel-2 px-1 rounded">{'{nome}'}</code> para o nome do lead e <code className="bg-panel-2 px-1 rounded">{'{link}'}</code> para o link rastreável.
                </p>
              </div>
            )}
            <div>
              <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Link rastreável (opcional)</label>
              <input
                type="text"
                value={config.trackableUrl || ''}
                onChange={(e) => onChange({ ...config, trackableUrl: e.target.value })}
                placeholder="https://exemplo.com/oferta"
                className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              />
              <p className="text-[11px] text-muted mt-1">
                Será usado quando a mensagem contiver <code className="bg-panel-2 px-1 rounded">{'{link}'}</code>. Os cliques são registrados.
              </p>
            </div>
          </>
        )}

        {node.data.blockType === 'condition' && (
          <div>
            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">O que verificar</label>
            <select
              value={config.conditionType || 'respondeu'}
              onChange={(e) => onChange({ ...config, conditionType: e.target.value })}
              className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            >
              {Object.entries(CONDITION_TYPE_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </div>
        )}

        {(node.data.blockType === 'wait' || node.data.blockType === 'condition') && (
          <div>
            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">
              {node.data.blockType === 'wait' ? 'Espera Minha Mensagem' : 'Espera Mensagem Dele'}
            </label>
            <div className="flex gap-2">
              <input
                type="number"
                min={0}
                value={config.value ?? 0}
                onChange={(e) => onChange({ ...config, value: Number(e.target.value) })}
                className="w-24 px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              />
              <select
                value={config.unit || 'minutes'}
                onChange={(e) => onChange({ ...config, unit: e.target.value })}
                className="flex-1 px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
              >
                {node.data.blockType === 'wait' && <option value="seconds">Segundos</option>}
                <option value="minutes">Minutos</option>
                <option value="hours">Horas</option>
                <option value="days">Dias</option>
              </select>
            </div>
            {node.data.blockType === 'condition' && (
              <p className="text-[11px] text-muted mt-1">
                Se a condição acima for satisfeita dentro desse período, segue pelo ramo "Sim". Caso contrário, pelo "Não".
              </p>
            )}
          </div>
        )}

        {node.data.blockType === 'move_stage' && (
          <div>
            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Mover o lead para</label>
            <select
              value={config.stageId || ''}
              onChange={(e) => {
                const stageId = e.target.value
                // Grava o nome junto com o id: é o que o nó exibe no canvas, e
                // evita ter que carregar a lista de etapas lá dentro.
                const stageName = stages.find((s) => s.id === stageId)?.name || ''
                onChange({ ...config, stageId, stageName })
              }}
              className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent"
            >
              <option value="">Selecione a etapa…</option>
              {stages.map((stage) => (
                <option key={stage.id} value={stage.id}>{stage.name}</option>
              ))}
            </select>
            <p className="text-[11px] text-muted mt-1">
              O lead é movido para essa coluna do Pipeline e a mudança fica registrada no histórico dele.
            </p>
          </div>
        )}

        {node.data.blockType === 'end' && (
          <p className="text-xs text-muted">Este bloco encerra a execução do funil para o lead.</p>
        )}
      </div>

      {node.data.blockType !== 'trigger' && (
        <div className="px-4 py-3 border-t border-line">
          <button
            onClick={onDelete}
            className="flex items-center justify-center gap-1.5 w-full text-sm font-semibold text-red-600 hover:bg-red-50 rounded-lg py-2 transition-colors"
          >
            <Trash size={16} />
            Remover bloco
          </button>
        </div>
      )}
    </div>
  )
}

// ── Main Editor ──────────────────────────────────────────────────────────────

export interface FunnelEditorHandle {
  getFlow: () => { nodes: FlowNode[]; edges: Edge[] }
}

export default function FunnelEditor({
  initialNodes,
  initialEdges,
  stages = [],
  funnelId,
  onChange,
}: {
  initialNodes: FlowNode[]
  initialEdges: Edge[]
  /** Etapas do pipeline, para o bloco "Mover de etapa". */
  stages?: StageOption[]
  /** Quando informado, o canvas busca os números reais de cada bloco. */
  funnelId?: string
  onChange: (nodes: FlowNode[], edges: Edge[]) => void
}) {
  const [nodes, setNodes] = useState<FlowNode[]>(initialNodes)
  const [edges, setEdges] = useState<Edge[]>(initialEdges)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [stats, setStats] = useState<Record<string, EstatisticasBloco>>({})

  /*
   * Números reais por bloco.
   *
   * Ficam fora do `nodes` porque `nodes` é o que se SALVA — misturar métrica ali
   * gravaria número de execução dentro do desenho do fluxo. Aqui eles são
   * costurados só na hora de desenhar (nodesComStats).
   */
  useEffect(() => {
    if (!funnelId) return
    let cancelado = false
    fetch(`/api/funnels/${funnelId}/metrics`)
      .then((r) => (r.ok ? r.json() : null))
      .then((json) => {
        if (cancelado || !json?.data) return
        const mapa: Record<string, EstatisticasBloco> = {}
        const garante = (id: string) => (mapa[id] ??= { enviado: 0, entregue: 0, respondeu: 0, clicou: 0 })
        for (const e of json.data.envios ?? []) {
          const alvo = garante(e.block_id)
          alvo.enviado = e.enviado
          alvo.entregue = e.entregue
        }
        for (const c of json.data.clicks ?? []) garante(c.block_id).clicou = c.clicados
        for (const r of json.data.responses ?? []) garante(r.block_id).respondeu = r.sim
        setStats(mapa)
      })
      .catch(() => { /* canvas sem números continua utilizável */ })
    return () => { cancelado = true }
  }, [funnelId])

  const nodesComStats = useMemo(
    () => nodes.map((n) => (stats[n.id] ? { ...n, data: { ...n.data, stats: stats[n.id] } } : n)),
    [nodes, stats]
  )

  const emit = useCallback((n: FlowNode[], e: Edge[]) => {
    onChange(n, e)
  }, [onChange])

  const onNodesChange = useCallback((changes: NodeChange[]) => {
    setNodes((prev) => {
      const next = applyNodeChanges(changes, prev) as FlowNode[]
      emit(next, edges)
      return next
    })
  }, [edges, emit])

  const onEdgesChange = useCallback((changes: EdgeChange[]) => {
    setEdges((prev) => {
      const next = applyEdgeChanges(changes, prev)
      emit(nodes, next)
      return next
    })
  }, [nodes, emit])

  const onConnect = useCallback((connection: Connection) => {
    // Sem rótulo colorido no fio: no ManyChat quem diz o que é cada saída é o
    // próprio cartão ("Respondeu" / "Não respondeu"), e o fio é só o traço que
    // liga. Rótulo repetido no meio da curva só polui o canvas.
    const color = connection.sourceHandle === 'yes'
      ? '#12B76A'
      : connection.sourceHandle === 'no'
        ? '#F04438'
        : '#98A2B3'
    setEdges((prev) => {
      const next = addEdge({
        ...connection,
        type: 'smoothstep',
        style: { stroke: color, strokeWidth: 1.5 },
      }, prev)
      emit(nodes, next)
      return next
    })
  }, [nodes, emit])

  const updateNodeConfig = useCallback((id: string, config: Record<string, any>) => {
    setNodes((prev) => {
      const next = prev.map((n) => n.id === id ? { ...n, data: { ...n.data, config } } : n)
      emit(next, edges)
      return next
    })
  }, [edges, emit])

  const deleteNode = useCallback((id: string) => {
    setNodes((prev) => {
      const next = prev.filter((n) => n.id !== id)
      setEdges((prevEdges) => {
        const nextEdges = prevEdges.filter((e) => e.source !== id && e.target !== id)
        emit(next, nextEdges)
        return nextEdges
      })
      return next
    })
    setSelectedId(null)
  }, [emit])

  const addNode = useCallback((blockType: FunnelBlockData['blockType']) => {
    const id = `tmp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
    const defaultConfig: Record<string, Record<string, any>> = {
      message: { text: '', trackableUrl: '' },
      wait: { value: 5, unit: 'minutes' },
      condition: { value: 60, unit: 'minutes' },
      move_stage: { stageId: '', stageName: '' },
      end: {},
      trigger: {},
    }
    const position = { x: 100 + nodes.length * 300, y: 100 + Math.random() * 80 }
    const newNode: FlowNode = { id, type: blockType, position, data: { blockType, config: defaultConfig[blockType] || {} } }
    setNodes((prev) => {
      const next = [...prev, newNode]
      emit(next, edges)
      return next
    })
  }, [nodes.length, edges, emit])

  const selectedNode = nodes.find((n) => n.id === selectedId) || null

  return (
    <ReactFlowProvider>
      <div className="relative w-full h-full">
        <ReactFlow
          nodes={nodesComStats}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeClick={(_, node) => setSelectedId(node.id)}
          onPaneClick={() => setSelectedId(null)}
          fitView
          fitViewOptions={{ padding: 0.25 }}
          deleteKeyCode={['Backspace', 'Delete']}
          // Curva suave em todo fio novo OU antigo — os que já estavam salvos no
          // banco não têm `type`, e sem isto continuariam retos no meio do resto.
          defaultEdgeOptions={{ type: 'smoothstep', style: { stroke: '#98A2B3', strokeWidth: 1.5 } }}
          proOptions={{ hideAttribution: true }}
          style={{ background: '#F7F8FA' }}
        >
          {/* Pontinhos bem discretos: dão a noção de deslocamento sem competir
              com os cartões, que é o que o ManyChat faz. */}
          <Background gap={22} size={1.4} color="#DCE0E8" />
          <Controls showInteractive={false} />
        </ReactFlow>

        {/* Toolbar to add new blocks */}
        <div className="absolute top-3 left-3 z-10 bg-panel border border-line rounded-xl shadow-sm p-2 flex flex-col gap-1.5">
          <p className="text-[11px] font-semibold text-muted uppercase tracking-wide px-1.5 mb-0.5">Adicionar bloco</p>
          <button onClick={() => addNode('message')} className="flex items-center gap-2 text-xs font-semibold text-muted hover:bg-panel-2 hover:text-accent-2 rounded-lg px-2 py-1.5 transition-colors">
            <Plus size={14} /> <ChatCircleDots size={14} weight="fill" style={{ color: '#3b82f6' }} /> Mensagem
          </button>
          <button onClick={() => addNode('wait')} className="flex items-center gap-2 text-xs font-semibold text-muted hover:bg-amber-50 hover:text-amber-600 rounded-lg px-2 py-1.5 transition-colors">
            <Plus size={14} /> <HourglassSimple size={14} weight="fill" style={{ color: '#f59e0b' }} /> Espera Minha Mensagem
          </button>
          <button onClick={() => addNode('condition')} className="flex items-center gap-2 text-xs font-semibold text-muted hover:bg-orange-50 hover:text-orange-600 rounded-lg px-2 py-1.5 transition-colors">
            <Plus size={14} /> <GitBranch size={14} weight="fill" style={{ color: '#f97316' }} /> Espera Mensagem Dele
          </button>
          <button onClick={() => addNode('move_stage')} className="flex items-center gap-2 text-xs font-semibold text-muted hover:bg-teal-500/10 hover:text-teal-400 rounded-lg px-2 py-1.5 transition-colors">
            <Plus size={14} /> <ArrowsLeftRight size={14} weight="fill" style={{ color: '#14b8a6' }} /> Mover de etapa
          </button>
          <button onClick={() => addNode('end')} className="flex items-center gap-2 text-xs font-semibold text-muted hover:bg-panel-2 rounded-lg px-2 py-1.5 transition-colors">
            <Plus size={14} /> <FlagCheckered size={14} weight="fill" style={{ color: '#6b7280' }} /> Fim
          </button>
        </div>

        {selectedNode && (
          <BlockEditorPanel
            node={selectedNode}
            stages={stages}
            onChange={(config) => updateNodeConfig(selectedNode.id, config)}
            onDelete={() => deleteNode(selectedNode.id)}
            onClose={() => setSelectedId(null)}
          />
        )}
      </div>
    </ReactFlowProvider>
  )
}

/**
 * Teste A/B/C de um bloco de mensagem.
 *
 * Fica escondido até alguém ligar: a maioria dos blocos manda um texto só, e um
 * editor de versões sempre à mostra transformaria o caso simples numa decisão.
 *
 * As letras (A, B, C) são o que aparece na tela de métricas, e vêm da POSIÇÃO —
 * assim uma versão removida no meio do teste não faz os números de antes e de
 * depois virarem a mesma linha com nomes trocados.
 */
function TesteDeMensagens({
  config,
  onChange,
}: {
  config: Record<string, any>
  onChange: (config: Record<string, any>) => void
}) {
  const variantes: { id: string; texto: string }[] = Array.isArray(config.variantes) ? config.variantes : []
  const ligado = variantes.length > 0
  const LETRAS = ['A', 'B', 'C', 'D', 'E']

  const salvar = (lista: { id: string; texto: string }[]) =>
    onChange({ ...config, variantes: lista.map((v, i) => ({ ...v, id: LETRAS[i] || String(i + 1) })) })

  return (
    <div className="border border-line rounded-lg p-3">
      <label className="flex items-start gap-2.5 cursor-pointer">
        <input
          type="checkbox"
          checked={ligado}
          onChange={(e) =>
            e.target.checked
              ? salvar([
                  { id: 'A', texto: config.text || '' },
                  { id: 'B', texto: '' },
                ])
              : onChange({ ...config, variantes: [], text: variantes[0]?.texto || config.text || '' })
          }
          className="mt-0.5 w-4 h-4 accent-[var(--blue)]"
        />
        <span className="min-w-0">
          <span className="block text-xs font-bold text-ink uppercase tracking-wide">Testar versões (A/B/C)</span>
          <span className="block text-[11px] text-muted leading-snug">
            Cada lead recebe uma versão sorteada. Em Métricas dá pra ver qual faz mais gente responder.
          </span>
        </span>
      </label>

      {ligado && (
        <div className="mt-3 space-y-3">
          {variantes.map((v, i) => (
            <div key={v.id || i}>
              <div className="flex items-center justify-between mb-1">
                <span className="text-xs font-bold text-accent-2">Versão {v.id || LETRAS[i]}</span>
                {variantes.length > 2 && (
                  <button
                    type="button"
                    onClick={() => salvar(variantes.filter((_, j) => j !== i))}
                    className="text-[11px] text-muted hover:text-ink"
                  >
                    remover
                  </button>
                )}
              </div>
              <textarea
                value={v.texto}
                onChange={(e) =>
                  salvar(variantes.map((outro, j) => (j === i ? { ...outro, texto: e.target.value } : outro)))
                }
                rows={5}
                placeholder={'Ex: Oi {nome}! Vi que você parou no meio…'}
                className="w-full px-3 py-2 border border-line rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-accent resize-none"
              />
            </div>
          ))}

          {variantes.length < 5 && (
            <button
              type="button"
              onClick={() => salvar([...variantes, { id: '', texto: '' }])}
              className="text-xs font-semibold text-accent-2 hover:underline"
            >
              + Acrescentar versão
            </button>
          )}

          <p className="text-[11px] text-muted leading-snug">
            Mude uma coisa por vez entre as versões (a abertura, a pergunta, o tamanho).
            Mudando tudo de uma vez, o resultado não diz o que causou a diferença.
          </p>
        </div>
      )}
    </div>
  )
}
