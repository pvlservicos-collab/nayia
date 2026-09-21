'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { FlowArrow, Plus, ArrowClockwise, ArrowSquareOut } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import NotAuthorized from '@/components/Shared/NotAuthorized'

interface FunnelSummary {
  id: string
  name: string
  // string, e não uma união fechada: o enum funnel_trigger no banco já tinha
  // 'geracaowhatsapp' e outros que este tipo não listava — o código comparava
  // com eles e o TS acusava "sem sobreposição". Com as fontes de lead entrando
  // no enum, manter a lista duplicada aqui só multiplicaria o problema; os
  // rótulos vêm de TRIGGER_LABELS, que já trata valor desconhecido.
  trigger: string
  is_active: boolean
  created_at: string
  metrics: {
    entradas: number
    mensagens_enviadas: number
    cliques: number
    cliques_total: number
    taxa_clique: number
  }
}

const TRIGGER_LABELS: Record<string, string> = {
  novo_pago: 'Novo Pago',
  novo_recuperacao: 'Novo Recuperação',
  lead_site_evento: 'Lead novo — Site Evento',
  lead_agenda_ascensao: 'Lead novo — Agenda Ascensão',
}

export default function FunnelsPage() {
  const router = useRouter()
  const { loading: authLoading, permissions, isMaster, roleName } = useAuth()
  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']
  const [funnels, setFunnels] = useState<FunnelSummary[]>([])
  const [loading, setLoading] = useState(true)
  const [creating, setCreating] = useState(false)
  const [showNewModal, setShowNewModal] = useState(false)
  const [newName, setNewName] = useState('')
  const [newTrigger, setNewTrigger] = useState<string>('lead_site_evento')

  const fetchFunnels = async () => {
    setLoading(true)
    try {
      const res = await fetch('/api/funnels')
      if (res.ok) {
        const { data } = await res.json()
        setFunnels(data || [])
      }
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchFunnels()
  }, [])

  const toggleActive = async (funnel: FunnelSummary) => {
    if (funnel.trigger === 'geracaowhatsapp') return
    setFunnels(prev => prev.map(f => f.id === funnel.id ? { ...f, is_active: !f.is_active } : f))
    try {
      const res = await fetch(`/api/funnels/${funnel.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isActive: !funnel.is_active }),
      })
      if (!res.ok) throw new Error()
    } catch {
      setFunnels(prev => prev.map(f => f.id === funnel.id ? { ...f, is_active: funnel.is_active } : f))
    }
  }

  const createFunnel = async () => {
    if (!newName.trim()) return
    setCreating(true)
    try {
      const res = await fetch('/api/funnels', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: newName.trim(), trigger: newTrigger }),
      })
      if (res.ok) {
        const { data } = await res.json()
        router.push(`/funnels/${data.id}`)
      }
    } finally {
      setCreating(false)
    }
  }

  if (!authLoading && !isAdmin && permissions && !permissions.settings?.view_funnels) {
    return <NotAuthorized />
  }

  return (
    <div className="h-full bg-panel flex flex-col">
      <div className="sticky top-0 z-10 bg-panel border-b border-line px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <FlowArrow size={20} weight="bold" className="text-muted" />
          <h1 className="text-lg font-bold text-ink">Funil de Mensagens</h1>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={fetchFunnels}
            className="flex items-center gap-1.5 text-xs font-semibold text-accent-2 hover:text-accent-2 transition-colors uppercase tracking-wide"
          >
            <ArrowClockwise size={14} weight="bold" />
            Atualizar
          </button>
          <button
            onClick={() => setShowNewModal(true)}
            className="flex items-center gap-1.5 bg-accent hover:bg-accent-2 text-white text-sm font-semibold px-3 py-1.5 rounded-lg transition-colors"
          >
            <Plus size={16} weight="bold" />
            Novo Funil
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto">
        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="w-6 h-6 border-2 border-line border-t-blue-500 rounded-full animate-spin" />
          </div>
        ) : funnels.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-muted gap-3">
            <FlowArrow size={48} weight="light" />
            <p className="text-sm font-medium">Nenhum funil criado ainda</p>
            <button
              onClick={() => setShowNewModal(true)}
              className="flex items-center gap-1.5 bg-accent hover:bg-accent-2 text-white text-sm font-semibold px-3 py-1.5 rounded-lg transition-colors"
            >
              <Plus size={16} weight="bold" />
              Criar primeiro funil
            </button>
          </div>
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="sticky top-0 bg-void border-b border-line">
              <tr className="text-left text-xs font-semibold text-muted uppercase tracking-wide">
                <th className="px-6 py-2.5">Nome</th>
                <th className="px-6 py-2.5">Gatilho</th>
                <th className="px-6 py-2.5">Status</th>
                <th className="px-6 py-2.5">Entradas</th>
                <th className="px-6 py-2.5">Mensagens enviadas</th>
                <th className="px-6 py-2.5">Cliques</th>
                <th className="px-6 py-2.5"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {funnels.map((funnel) => (
                <tr
                  key={funnel.id}
                  className="hover:bg-void cursor-pointer"
                  onClick={() => router.push(`/funnels/${funnel.id}`)}
                >
                  <td className="px-6 py-3 font-medium text-ink">{funnel.name}</td>
                  <td className="px-6 py-3 text-muted">{TRIGGER_LABELS[funnel.trigger] || funnel.trigger}</td>
                  <td className="px-6 py-3">
                    <button
                      onClick={(e) => { e.stopPropagation(); toggleActive(funnel) }}
                      disabled={funnel.trigger === 'geracaowhatsapp'}
                      title={funnel.trigger === 'geracaowhatsapp' ? 'Fluxo padrão: não pode ser desativado' : undefined}
                      className={`relative inline-flex h-5 w-9 items-center rounded-full transition-colors ${funnel.is_active ? 'bg-emerald-500' : 'bg-panel-2'} ${funnel.trigger === 'geracaowhatsapp' ? 'cursor-not-allowed opacity-80' : ''}`}
                    >
                      <span className={`inline-block h-4 w-4 transform rounded-full bg-panel transition-transform ${funnel.is_active ? 'translate-x-4.5' : 'translate-x-0.5'}`} />
                    </button>
                    <span className={`ml-2 text-xs font-semibold ${funnel.is_active ? 'text-emerald-600' : 'text-muted'}`}>
                      {funnel.is_active ? 'Ativo' : 'Inativo'}
                    </span>
                    {funnel.trigger === 'geracaowhatsapp' && (
                      <span className="ml-2 text-[10px] text-muted">🔒 padrão</span>
                    )}
                  </td>
                  <td className="px-6 py-3 text-muted">{funnel.metrics.entradas}</td>
                  <td className="px-6 py-3 text-muted">{funnel.metrics.mensagens_enviadas}</td>
                  <td className="px-6 py-3 text-muted">
                    {funnel.metrics.cliques}/{funnel.metrics.cliques_total}
                    {funnel.metrics.cliques_total > 0 && (
                      <span className="text-muted ml-1">({Math.round(funnel.metrics.taxa_clique * 100)}%)</span>
                    )}
                  </td>
                  <td className="px-6 py-3 text-right">
                    <ArrowSquareOut size={16} className="text-muted" />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </div>

      {showNewModal && (
        <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50" onClick={() => setShowNewModal(false)}>
          <div className="bg-panel rounded-xl shadow-xl p-6 w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
            <h2 className="text-base font-bold text-ink mb-4">Novo Funil</h2>

            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Nome</label>
            <input
              type="text"
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Ex: Recuperação PIX"
              className="w-full px-3 py-2 border border-line rounded-lg text-sm mb-4 focus:outline-none focus:ring-2 focus:ring-accent"
              autoFocus
            />

            <label className="block text-xs font-semibold text-muted uppercase tracking-wide mb-1.5">Gatilho</label>
            <select
              value={newTrigger}
              onChange={(e) => setNewTrigger(e.target.value as any)}
              className="w-full px-3 py-2 border border-line rounded-lg text-sm mb-6 focus:outline-none focus:ring-2 focus:ring-accent"
            >
              {Object.entries(TRIGGER_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>

            <div className="flex justify-end gap-2">
              <button
                onClick={() => setShowNewModal(false)}
                className="px-3 py-1.5 text-sm font-semibold text-muted hover:bg-void rounded-lg transition-colors"
              >
                Cancelar
              </button>
              <button
                onClick={createFunnel}
                disabled={creating || !newName.trim()}
                className="px-3 py-1.5 text-sm font-semibold bg-accent hover:bg-accent-2 disabled:opacity-50 text-white rounded-lg transition-colors"
              >
                {creating ? 'Criando...' : 'Criar e editar'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
