'use client'

import { ChartBar } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import NotAuthorized from '@/components/Shared/NotAuthorized'

export default function MetricsPage() {
  const { loading: authLoading, permissions, isMaster, roleName } = useAuth()
  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']

  if (!authLoading && !isAdmin && permissions && !permissions.settings?.view_metrics) {
    return <NotAuthorized />
  }

  return (
    <div className="h-full bg-panel flex flex-col">
      <div className="sticky top-0 z-10 bg-panel border-b border-line px-6 py-4 flex items-center gap-2">
        <ChartBar size={20} weight="bold" className="text-muted" />
        <h1 className="text-lg font-bold text-ink">Métricas</h1>
      </div>
      <div className="flex-1 flex items-center justify-center text-muted">
        <p className="text-sm">Nenhuma métrica disponível.</p>
      </div>
    </div>
  )
}
