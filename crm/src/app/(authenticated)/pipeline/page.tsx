'use client'

import { useAuth } from '@/hooks'
import { usePipelineFilters } from '@/contexts/FilterContext'
import { PipelineBoard } from '@/components/Pipeline'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

export default function PipelinePage() {
  const { organizationId, loading, permissions, isMaster, roleName } = useAuth()
  const { filters } = usePipelineFilters()

  // Security Check Check
  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']
  if (!loading && !isAdmin && permissions && !permissions.settings?.view_pipeline) {
    return <NotAuthorized />
  }

  if (loading || (!isAdmin && !permissions)) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-56px)]">
        <LoadingSpinner text="Carregando..." size="lg" />
      </div>
    )
  }

  if (!organizationId) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-56px)]">
        <p className="text-muted">Nenhuma organização encontrada. Execute o seed.sql no Supabase.</p>
      </div>
    )
  }

  return (
    <>
      <PipelineBoard organizationId={organizationId} filters={filters} />
    </>
  )
}
