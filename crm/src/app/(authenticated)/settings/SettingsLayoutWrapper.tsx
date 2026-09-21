'use client'

import { useEffect } from 'react'
import Link from 'next/link'
import { usePathname, useRouter } from 'next/navigation'
import { CaretLeft } from '@phosphor-icons/react'
import SettingsSidebar from './SettingsSidebar'
import SettingsAccessGuard from '@/components/Settings/SettingsAccessGuard'
import { useIsMobile } from '@/hooks/useIsMobile'

export default function SettingsLayoutWrapper({
    children,
}: {
    children: React.ReactNode
}) {
    const pathname = usePathname()
    const router = useRouter()
    const isMobile = useIsMobile()
    const isRoot = pathname === '/settings'

    // No computador a raiz sempre abre em "Perfil da Organização" (não faz sentido mostrar
    // um painel vazio do lado da barra lateral); no celular a raiz é a própria lista de seções.
    // Checa a media query direto (em vez de depender do estado do useIsMobile) porque o efeito
    // deste hook e o efeito abaixo disparam no mesmo commit inicial — usar o estado dele aqui
    // correria o risco de redirecionar no celular também, antes dele se corrigir pra `true`.
    useEffect(() => {
        if (!isRoot) return
        const isMobileNow = window.matchMedia('(max-width: 767px)').matches
        if (!isMobileNow) router.replace('/settings/organization')
    }, [isRoot, router])

    // If the user is on the User Profile settings, do NOT show the organizational settings sidebar
    if (pathname === '/settings/profile') {
        return (
            <div className="min-h-[calc(100dvh-3.5rem)]">
                <main className="p-4 sm:p-8 lg:p-12 xl:p-16 overflow-y-auto w-full flex justify-center">
                    <div className="w-full max-w-4xl">
                        {children}
                    </div>
                </main>
            </div>
        )
    }

    if (isMobile) {
        // Raiz (/settings): lista de seções em tela cheia — igual à lista de conversas do Chat.
        if (isRoot) {
            return (
                <SettingsAccessGuard>
                    <div className="min-h-[calc(100dvh-3.5rem)] p-4">
                        <SettingsSidebar />
                    </div>
                </SettingsAccessGuard>
            )
        }

        // Seção específica: conteúdo em tela cheia, sem a barra lateral, com botão de voltar.
        return (
            <SettingsAccessGuard>
                <div className="min-h-[calc(100dvh-3.5rem)]">
                    <div className="sticky top-14 z-10 glass-soft rounded-none border-x-0 border-t-0 px-4 h-12 flex items-center">
                        <Link href="/settings" className="flex items-center gap-1.5 text-sm font-medium text-muted">
                            <CaretLeft size={16} weight="bold" />
                            Configurações
                        </Link>
                    </div>
                    <main className="p-4">
                        {children}
                    </main>
                </div>
            </SettingsAccessGuard>
        )
    }

    // Aguarda o redirect do useEffect acima em vez de piscar a barra lateral com painel vazio
    if (isRoot) return null

    const isWideSection = pathname.startsWith('/settings/leads') || pathname.startsWith('/settings/log')

    return (
        <SettingsAccessGuard>
            <div className="flex min-h-[calc(100vh-3.5rem)]">
                {/* Sidebar Navigation */}
                <aside className="w-64 surface-rail border-r border-line min-h-[calc(100vh-3.5rem)]">
                    <div className="p-4">
                        <SettingsSidebar />
                    </div>
                </aside>

                {/* Main Content Area
                    max-w-3xl e a largura de leitura das telas de formulario. A de
                    Leads e uma planilha de ate 12 colunas: ali a restricao so
                    espremeria a tabela num scroll horizontal desnecessario. */}
                <main className="flex-1 p-8 lg:p-12 xl:p-16 overflow-y-auto">
                    <div className={isWideSection ? 'max-w-none' : 'max-w-3xl'}>
                        {children}
                    </div>
                </main>
            </div>
        </SettingsAccessGuard>
    )
}
