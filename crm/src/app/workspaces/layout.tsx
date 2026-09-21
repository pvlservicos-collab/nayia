import { AuthProvider } from '@/contexts/AuthContext'
import AuthGuard from '@/components/Auth/AuthGuard'

export default function WorkspacesLayout({
    children,
}: {
    children: React.ReactNode
}) {
    return (
        <AuthGuard>
            <AuthProvider>
                {children}
            </AuthProvider>
        </AuthGuard>
    )
}
