'use client'

import { useState } from 'react'
import { useAuth } from '@/hooks'
import RolesSidebar from '@/components/Settings/RolesSidebar'
import RolePermissionsPanel from '@/components/Settings/RolePermissionsPanel'
import MembersPanel from '@/components/Settings/MembersPanel'

export default function MembersSettingsPage() {
    const { organizationId, loading: authLoading } = useAuth()
    const [activeTab, setActiveTab] = useState<'members' | 'roles'>('roles') // Defaulting to roles to work on it first
    const [selectedRoleId, setSelectedRoleId] = useState<string | null>(null)

    const showLoading = authLoading || !organizationId

    return (
        <div className="max-w-5xl space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-ink pb-1">Membros e Permissões</h1>
                <p className="text-sm text-muted">Gerencie o acesso da sua equipe e os cargos disponíveis na organização.</p>
            </div>

            {/* Tabs */}
            <div className="flex items-center gap-6 border-b border-line">
                <button
                    onClick={() => setActiveTab('members')}
                    className={`pb-3 text-sm font-medium transition-colors border-b-2 ${activeTab === 'members'
                        ? 'border-accent text-accent-2'
                        : 'border-transparent text-muted hover:text-ink'
                        }`}
                >
                    Membros
                </button>
                <button
                    onClick={() => setActiveTab('roles')}
                    className={`pb-3 text-sm font-medium transition-colors border-b-2 ${activeTab === 'roles'
                        ? 'border-accent text-accent-2'
                        : 'border-transparent text-muted hover:text-ink'
                        }`}
                >
                    Cargos e Permissões
                </button>
            </div>

            <div className="pt-2">
                {showLoading ? (
                    <div className="flex items-center justify-center h-48">
                        <p className="text-muted text-sm">Carregando...</p>
                    </div>
                ) : activeTab === 'members' ? (
                    <div>
                        <MembersPanel organizationId={organizationId!} />
                    </div>
                ) : (
                    <div className="flex flex-col md:flex-row gap-8 items-start">
                        {/* Area de Cargos e Permissoes */}
                        <div className="w-full md:w-64 flex-shrink-0">
                            <RolesSidebar
                                organizationId={organizationId!}
                                selectedRoleId={selectedRoleId}
                                onSelectRole={setSelectedRoleId}
                            />
                        </div>
                        <div className="flex-1 min-w-0 w-full">
                            <RolePermissionsPanel
                                organizationId={organizationId!}
                                selectedRoleId={selectedRoleId}
                            />
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
