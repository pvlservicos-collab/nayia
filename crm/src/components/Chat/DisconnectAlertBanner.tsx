'use client'

import { useState, useEffect, useCallback } from 'react'
import { WarningCircle, X } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { usePusherChannel } from '@/hooks/usePusher'

/**
 * Aviso fixo em cima do chat quando o webhook da Z-API avisa que a instância
 * desconectou (ver /api/webhooks/zapi e a ação "fechar_aviso" em
 * /api/integrations/zapi). Fica até um humano fechar no X — nem reconectar
 * sozinha desliga: foi assim que a queda de hoje passou batida até um lead
 * reclamar que não recebeu resposta.
 */
export default function DisconnectAlertBanner() {
  const { organizationId } = useAuth()
  const [active, setActive] = useState(false)
  const [closing, setClosing] = useState(false)

  const fetchState = useCallback(async () => {
    if (!organizationId) return
    try {
      const res = await fetch('/api/integrations/zapi')
      if (!res.ok) return
      const data = await res.json()
      setActive(!!data?.alerta_desconexao)
    } catch {}
  }, [organizationId])

  useEffect(() => { fetchState() }, [fetchState])

  usePusherChannel(organizationId ? `org-${organizationId}` : '', {
    'integration.disconnect_alert': (data: any) => setActive(!!data?.active),
  })

  const fechar = async () => {
    setClosing(true)
    try {
      const res = await fetch('/api/integrations/zapi', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ acao: 'fechar_aviso' }),
      })
      if (res.ok) setActive(false)
    } finally {
      setClosing(false)
    }
  }

  if (!active) return null

  return (
    <div className="flex items-center gap-2 bg-red-600 text-white px-4 py-2.5 text-sm font-semibold flex-shrink-0">
      <WarningCircle size={18} weight="fill" className="flex-shrink-0" />
      <span className="flex-1">INSTÂNCIA DESCONECTADA! Avisar Pedro ou Augusto</span>
      <button
        onClick={fechar}
        disabled={closing}
        className="w-6 h-6 flex items-center justify-center rounded hover:bg-white/20 transition-colors disabled:opacity-50 flex-shrink-0"
        aria-label="Fechar aviso"
      >
        <X size={16} weight="bold" />
      </button>
    </div>
  )
}
