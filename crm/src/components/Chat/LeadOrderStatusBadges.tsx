'use client'

import { useState, useEffect } from 'react'
import { PAYMENT_STATUS_META, DELIVERY_STATUS_META, TONE_STYLES } from '@/lib/orderStatus'

interface LatestOrder {
  payment_status: string
  delivery_status: string
}

/** Selos compactos e somente-leitura de pagamento/entrega, pra usar ao lado do nome do lead. */
export default function LeadOrderStatusBadges({ leadId }: { leadId: string }) {
  const [order, setOrder] = useState<LatestOrder | null>(null)

  useEffect(() => {
    let cancelled = false
    fetch(`/api/orders?lead_id=${leadId}&limit=1`)
      .then(res => (res.ok ? res.json() : { data: [] }))
      .then(({ data }) => { if (!cancelled) setOrder(data?.[0] || null) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [leadId])

  if (!order) return null

  return (
    <div className="flex items-center gap-1 flex-shrink-0">
      <span
        className="text-[10px] font-bold px-1.5 py-0.5 rounded-full whitespace-nowrap"
        style={TONE_STYLES[PAYMENT_STATUS_META[order.payment_status]?.tone || 'warning']}
      >
        {PAYMENT_STATUS_META[order.payment_status]?.label || order.payment_status}
      </span>
      <span
        className="text-[10px] font-bold px-1.5 py-0.5 rounded-full whitespace-nowrap"
        style={TONE_STYLES[DELIVERY_STATUS_META[order.delivery_status]?.tone || 'warning']}
      >
        {DELIVERY_STATUS_META[order.delivery_status]?.label || order.delivery_status}
      </span>
    </div>
  )
}
