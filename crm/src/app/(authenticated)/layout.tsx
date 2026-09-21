'use client'

import Navbar from '@/components/Shared/Navbar'
import { FilterProvider } from '@/contexts/FilterContext'
import AuthGuard from '@/components/Auth/AuthGuard'
import InstallAppBanner from '@/components/Shared/InstallAppBanner'
import SomNovoLead from '@/components/Shared/SomNovoLead'

/**
 * Layout for all authenticated pages (pipeline, chat, settings, etc.)
 * Wraps children with AuthGuard (redirects if not logged in) and Navbar.
 *
 * AuthProvider/NotificationProvider já vêm do root layout (src/app/layout.tsx),
 * que envolve toda a árvore — não remontar aqui evita fetches duplicados de
 * /api/users/me em toda navegação (o contexto interno era descartado mesmo,
 * já que useAuth()/useNotifications() resolvem pro provider mais próximo).
 *
 * LeadsProvider não fica mais aqui — só Pipeline e Chat usam a lista de leads,
 * então cada um tem seu próprio layout local (pipeline/layout.tsx, chat/layout.tsx,
 * chat-evolution/layout.tsx) que o monta. As demais páginas deixam de pagar o
 * custo de /api/leads?returnAll=true em toda navegação.
 */
export default function AuthenticatedLayout({
    children,
}: {
    children: React.ReactNode
}) {
    return (
        <AuthGuard>
            <FilterProvider>
                {/* surface-app é o degradê cinza→preto do fundo do app; bg-void
                    fica como cor de base pro caso do degradê não pintar (ex:
                    print/PDF, que costuma descartar background-image). */}
                <div className="flex flex-col h-[100dvh] bg-void surface-app">
                    <Navbar />
                    {/* Espaço embaixo pra não ficar atrás da barra de navegação inferior fixa (celular) */}
                    <main className="flex-1 overflow-auto scrollbar-hide pb-[calc(4rem+env(safe-area-inset-bottom))] md:pb-0">
                        {children}
                    </main>
                </div>
                <InstallAppBanner />
                {/* Aviso sonoro de lead novo — fica no layout, e não numa página,
                    porque quem atende passa o dia no Chat ou no Pipeline. */}
                <SomNovoLead />
            </FilterProvider>
        </AuthGuard>
    )
}
