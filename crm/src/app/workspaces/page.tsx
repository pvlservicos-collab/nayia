'use client'

/**
 * Workspaces page — substitui supabase.auth.getSession + supabase.from
 * Agora usa useSession + fetch para API routes
 */
import { useEffect, useState } from 'react'
import { useSession, signOut } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

interface Organization {
  id: string
  name: string
  logo_url?: string
}

interface Member {
  id: string
  organization_id: string
  organization: Organization
}

export default function WorkspacesPage() {
  const { data: session, status } = useSession()
  const router = useRouter()
  const [members, setMembers] = useState<Member[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (status === 'unauthenticated') { router.push('/login'); return }
    if (status !== 'authenticated') return

    async function loadWorkspaces() {
      try {
        const res = await fetch('/api/workspaces')
        if (!res.ok) throw new Error('Falha ao carregar workspaces')
        const data = await res.json()
        setMembers(data.data || [])
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erro desconhecido')
      } finally {
        setLoading(false)
      }
    }

    loadWorkspaces()
  }, [status])

  const handleSelectWorkspace = (orgId: string) => {
    if (typeof window !== 'undefined') localStorage.setItem('follem_active_org', orgId)
    router.push('/')
  }

  const handleLogout = async () => {
    await signOut({ callbackUrl: '/login' })
  }

  if (loading || status === 'loading') {
    return (
      <div className="flex items-center justify-center h-screen">
        <LoadingSpinner text="Carregando workspaces..." size="lg" />
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-4">
      <div className="w-full max-w-md">
        <h1 className="text-2xl font-bold text-gray-900 mb-2 text-center">Seus Workspaces</h1>
        <p className="text-gray-500 text-sm text-center mb-8">Selecione uma organização para continuar</p>

        {error && (
          <div className="bg-red-50 border border-red-200 text-red-700 text-sm rounded-lg px-4 py-3 mb-4">
            {error}
          </div>
        )}

        <div className="space-y-2">
          {members.map((m) => (
            <button
              key={m.id}
              onClick={() => handleSelectWorkspace(m.organization_id)}
              className="w-full flex items-center gap-3 bg-white border border-gray-200 rounded-xl p-4 hover:border-yellow-400 hover:shadow-sm transition-all text-left"
            >
              {m.organization?.logo_url ? (
                <img src={m.organization.logo_url} alt="" className="w-10 h-10 rounded-lg object-cover" />
              ) : (
                <div className="w-10 h-10 rounded-lg bg-[#f9f506] flex items-center justify-center font-bold text-gray-900">
                  {(m.organization?.name || 'W')[0].toUpperCase()}
                </div>
              )}
              <span className="font-medium text-gray-900">{m.organization?.name || 'Workspace'}</span>
            </button>
          ))}

          {members.length === 0 && (
            <div className="text-center text-gray-500 text-sm py-8">
              Você não faz parte de nenhuma organização.
            </div>
          )}
        </div>

        <button
          onClick={handleLogout}
          className="w-full mt-6 text-sm text-gray-500 hover:text-gray-700 transition-colors"
        >
          Sair da conta
        </button>
      </div>
    </div>
  )
}
