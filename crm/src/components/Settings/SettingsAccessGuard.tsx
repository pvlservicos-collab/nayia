'use client'

import { useAuth } from '@/hooks'
import NotAuthorized from '@/components/Shared/NotAuthorized'

export default function SettingsAccessGuard({ children }: { children: React.ReactNode }) {
    const { loading, permissions, isMaster, roleName } = useAuth()

    // While auth is loading, render children immediately so the page shell appears instantly
    if (loading) {
        return <>{children}</>
    }

    const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']

    if (!isAdmin && permissions && !permissions.settings?.view_settings) {
        return (
            <div className="pt-12">
                <NotAuthorized />
            </div>
        )
    }

    return <>{children}</>
}

