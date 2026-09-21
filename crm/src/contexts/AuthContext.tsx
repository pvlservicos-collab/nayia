'use client'

/**
 * AuthContext — substitui Supabase Auth
 * Usa NextAuth (useSession) como fonte de verdade
 */
import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react'
import { useSession } from 'next-auth/react'
import { OrganizationMember } from '@/lib/types'

interface AuthContextType {
  user: { id: string; email: string; name?: string | null; image?: string | null } | null
  currentOrganization: OrganizationMember | null
  organizationId: string | null
  roleName: string | null
  permissions: any
  isMaster: boolean
  loading: boolean
  error: string | null
  profileName: string | null
  // onboardingCompleted null = ainda não sabemos (carregando OU erro/sem org — os dois
  // casos precisam de tratamento igual: nunca travar o app, ver OnboardingGate).
  // onboardingStatusLoaded existe separado porque esse null sozinho não distingue
  // "ainda buscando" de "resolvido de forma ambígua".
  onboardingCompleted: boolean | null
  onboardingStatusLoaded: boolean
}

export const AuthContext = createContext<AuthContextType>({
  user: null,
  currentOrganization: null,
  organizationId: null,
  roleName: null,
  permissions: null,
  isMaster: false,
  loading: true,
  error: null,
  profileName: null,
  onboardingCompleted: null,
  onboardingStatusLoaded: false,
})

export function AuthProvider({ children }: { children: ReactNode }) {
  const { data: session, status } = useSession()
  const [currentOrganization, setCurrentOrganization] = useState<OrganizationMember | null>(null)
  const [organizationId, setOrganizationId] = useState<string | null>(null)
  const [roleName, setRoleName] = useState<string | null>(null)
  const [permissions, setPermissions] = useState<any>(null)
  const [error, setError] = useState<string | null>(null)
  const [onboardingCompleted, setOnboardingCompleted] = useState<boolean | null>(null)
  const [onboardingStatusLoaded, setOnboardingStatusLoaded] = useState(false)
  const [organizacaoCarregando, setOrganizacaoCarregando] = useState(true)

  /**
   * `loading` cobre a sessão E a organização.
   *
   * Antes era só `status === 'loading'`, que fala apenas da sessão do NextAuth.
   * A organização vem de um fetch separado (`/api/users/me`), então existia uma
   * janela em que a sessão já tinha resolvido e a organização ainda não: nela,
   * `organizationId` era null e TODA tela protegida mostrava "Nenhuma
   * organização encontrada. Execute o seed.sql" — a primeira coisa que a pessoa
   * via ao abrir o chat era uma mensagem de erro de instalação.
   */
  const loading = status === 'loading' || organizacaoCarregando

  const user = session?.user
    ? {
        id: session.user.id as string,
        email: session.user.email as string,
        name: session.user.name,
        image: session.user.image,
      }
    : null

  const isMaster = (session?.user as any)?.isSuperadmin || false
  const profileName = session?.user?.name || null

  useEffect(() => {
    if (!user) {
      setCurrentOrganization(null)
      setOrganizationId(null)
      setRoleName(null)
      setPermissions(null)
      setOnboardingCompleted(null)
      setOnboardingStatusLoaded(false)
      // Sem sessão não há o que carregar — deixar `true` aqui prenderia a tela
      // de login num spinner eterno.
      setOrganizacaoCarregando(false)
      return
    }

    setOrganizacaoCarregando(true)

    async function loadOrganization() {
      try {
        const storedOrgId = typeof window !== 'undefined' ? localStorage.getItem('follem_active_org') : null
        const url = storedOrgId
          ? `/api/users/me?org_id=${storedOrgId}`
          : '/api/users/me'

        const res = await fetch(url)
        if (!res.ok) return

        const data = await res.json()
        if (data?.member) {
          setCurrentOrganization(data.member)
          setOrganizationId(data.member.organization_id)
          setRoleName(data.role?.name || null)
          setPermissions(data.role?.permissions || null)
          setOnboardingCompleted(data.onboarding_completed ?? false)
          if (typeof window !== 'undefined') {
            localStorage.setItem('follem_active_org', data.member.organization_id)
          }
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erro ao carregar organização')
      } finally {
        setOnboardingStatusLoaded(true)
        // No finally, não no sucesso: se o fetch falhar, a tela precisa sair do
        // spinner e mostrar o estado real em vez de girar pra sempre.
        setOrganizacaoCarregando(false)
      }
    }

    loadOrganization()
  }, [user?.id])

  return (
    <AuthContext.Provider
      value={{
        user,
        currentOrganization,
        organizationId,
        roleName,
        permissions,
        isMaster,
        loading,
        error,
        profileName,
        onboardingCompleted,
        onboardingStatusLoaded,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}
