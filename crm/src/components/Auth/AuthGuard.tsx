'use client'

/**
 * AuthGuard — substitui verificação de sessão Supabase
 * Usa useSession do NextAuth
 */
import { useEffect, ReactNode } from 'react'
import { useSession } from 'next-auth/react'
import { useRouter } from 'next/navigation'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

/**
 * Segunda barreira, no cliente: o middleware já redireciona quem não tem cookie
 * de sessão, mas ele não roda em navegação client-side do Next. Sem isto, uma
 * sessão que expira com a aba aberta deixaria a pessoa numa tela que parece
 * funcionar e só devolve 401 em toda chamada.
 */
export default function AuthGuard({ children }: { children: ReactNode }) {
  const { data: session, status } = useSession()
  const router = useRouter()

  useEffect(() => {
    if (status === 'unauthenticated') {
      router.push('/api/auth/entrar?callbackUrl=' + encodeURIComponent(window.location.pathname))
    }
  }, [status, router])

  if (status === 'loading') {
    return (
      <div className="flex items-center justify-center h-screen bg-void">
        <LoadingSpinner text="Carregando..." size="lg" />
      </div>
    )
  }

  if (!session) return null

  return <>{children}</>
}
