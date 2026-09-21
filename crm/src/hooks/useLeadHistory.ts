'use client'

import { useState, useEffect, useCallback } from 'react'
import { PAYMENT_STATUS_META } from '@/lib/orderStatus'

export interface HistoryEvent {
  id: string
  type: 'conversation' | 'automation' | 'stage_move' | 'value_change' | 'lead_created' | 'order'
  timestamp: string
  actorName: string | null
  actorAvatar: string | null
  description: string
  secondaryLabel?: string
  meta?: Record<string, any>
}

export function useLeadHistory(organizationId: string, leadId: string) {
  const [events, setEvents] = useState<HistoryEvent[]>([])
  const [loading, setLoading] = useState(true)

  const fetchHistory = useCallback(async () => {
    if (!organizationId || !leadId) { setEvents([]); setLoading(false); return }
    try {
      setLoading(true)
      const res = await fetch(`/api/leads/${leadId}/history`)
      if (!res.ok) { setEvents([]); return }
      const { data: activities, stageHistory, orders, lead } = await res.json()

      const unified: HistoryEvent[] = []

      for (const a of (activities || [])) {
        const metadata = a.metadata || {}
        const source = metadata.source

        let type: HistoryEvent['type'] = 'conversation'
        let description = ''
        let secondaryLabel: string | undefined
        let shouldInclude = false

        if (a.type === 'system' || a.type === 'system_note') {
          if (metadata.source === 'custom_field' || metadata.source === 'rename' || a.type === 'system_note') {
            type = 'value_change'; description = a.content || 'Atualização de campo'; secondaryLabel = 'Edição'; shouldInclude = true
          } else {
            type = 'automation'; description = a.content || 'Notificação do Sistema'; secondaryLabel = 'Automação'; shouldInclude = true
          }
        } else if ((a.type === 'whatsapp' || a.type === 'email') && (source === 'automation' || source === 'system')) {
          type = 'automation'
          const senderName = metadata.sender_name || 'Sistema'
          description = `Notificação gerada via ${senderName}`
          if (a.content) description += ` — "${a.content.length > 60 ? a.content.slice(0, 60) + '…' : a.content}"`
          secondaryLabel = 'Automação'; shouldInclude = true
        } else if (a.type === 'value_change' || a.type === 'lead_update') {
          type = 'value_change'; description = a.content || 'Atualização de campo'; secondaryLabel = 'Edição'; shouldInclude = true
        }

        if (shouldInclude) {
          unified.push({ id: a.id, type, timestamp: a.created_at || a.createdAt, actorName: null, actorAvatar: null, description, secondaryLabel, meta: metadata })
        }
      }

      for (const h of (stageHistory || [])) {
        const fromName = h.fromStageName || 'Desconhecido'
        const toName = h.toStageName || 'Desconhecido'
        const description = !h.fromStageId ? `Lead adicionado ao estágio ${toName}` : `Negócio movido ${fromName} para ${toName}`
        unified.push({
          id: h.id,
          type: 'stage_move',
          timestamp: h.moved_at || h.movedAt,
          actorName: null,
          actorAvatar: null,
          description,
          secondaryLabel: 'Mudança de Etapa',
        })
      }

      for (const o of (orders || [])) {
        const itemsSummary = (o.items || [])
          .map((i: { productName: string; quantity: number }) => (i.quantity > 1 ? `${i.quantity}x ${i.productName}` : i.productName))
          .join(', ') || 'Pedido sem itens'
        const total = Number(o.totalValue).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
        const paymentLabel = PAYMENT_STATUS_META[o.paymentStatus]?.label || o.paymentStatus

        unified.push({
          id: `order-${o.id}`,
          type: 'order',
          timestamp: o.createdAt,
          actorName: null,
          actorAvatar: null,
          description: `Compra registrada — ${itemsSummary} — ${total}`,
          secondaryLabel: paymentLabel,
        })
      }

      if (lead) {
        unified.push({
          id: `lead-created-${leadId}`,
          type: 'lead_created',
          timestamp: lead.createdAt || lead.created_at,
          actorName: null,
          actorAvatar: null,
          description: 'Lead criado',
          secondaryLabel: lead.value ? `R$ ${Number(lead.value).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}` : undefined,
        })
      }

      unified.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
      setEvents(unified)
    } catch (err) {
      console.error('Failed to fetch lead history:', err)
      setEvents([])
    } finally {
      setLoading(false)
    }
  }, [organizationId, leadId])

  useEffect(() => {
    fetchHistory()
  }, [fetchHistory])

  return { events, loading, refresh: fetchHistory }
}
