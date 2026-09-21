'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
    Buildings,
    UsersThree,
    TreeStructure,
    PencilSimpleLine,
    Tag,
    ShareNetwork,
    Bell,
    Package,
    Lightning,
    Table,
    ClipboardText,
    Robot,
} from '@phosphor-icons/react'

const SETTINGS_SECTIONS = [
    { label: 'Perfil da Organização', href: '/settings/organization', icon: Buildings },
    { label: 'Membros e Permissões', href: '/settings/members', icon: UsersThree },
    { label: 'Configurações do Pipeline', href: '/settings/pipelines', icon: TreeStructure },
    { label: 'Leads', href: '/settings/leads', icon: Table },
    { label: 'Log de eventos', href: '/settings/log', icon: ClipboardText },
    { label: 'Inteligência Artificial', href: '/settings/ia', icon: Robot },
    { label: 'Campos Customizados', href: '/settings/custom-fields', icon: PencilSimpleLine },
    { label: 'Tags', href: '/settings/tags', icon: Tag },
    { label: 'Respostas Rápidas', href: '/settings/quick-replies', icon: Lightning },
    { label: 'Produtos', href: '/settings/products', icon: Package },
    { label: 'Integrações', href: '/settings/integrations', icon: ShareNetwork },
    { label: 'Notificações', href: '/settings/notifications', icon: Bell },
]

export default function SettingsSidebar() {
    const pathname = usePathname()

    return (
        <nav className="space-y-1">
            {SETTINGS_SECTIONS.map((section) => {
                const isActive = pathname === section.href || pathname.startsWith(`${section.href}/`)
                const Icon = section.icon

                return (
                    <Link
                        key={section.href}
                        href={section.href}
                        className={`flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-colors border ${isActive
                            ? 'bg-graphite-6 border-white/15 text-accent-2'
                            : 'border-transparent text-muted hover:bg-white/[0.06] hover:text-ink'
                            }`}
                    >
                        <Icon size={20} weight={isActive ? "fill" : "regular"} className={isActive ? "text-accent-2" : "text-muted"} />
                        {section.label}
                    </Link>
                )
            })}
        </nav>
    )
}
