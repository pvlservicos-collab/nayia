'use client'

import { Suspense, useState, useEffect } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { signIn } from 'next-auth/react'

type TokenState = 'checking' | 'valid' | 'invalid'

function AtivarContaForm() {
    const router = useRouter()
    const searchParams = useSearchParams()
    const token = searchParams.get('token')

    const [tokenState, setTokenState] = useState<TokenState>('checking')
    const [orgName, setOrgName] = useState('')

    const [fullName, setFullName] = useState('')
    const [email, setEmail] = useState('')
    const [password, setPassword] = useState('')
    const [confirmPassword, setConfirmPassword] = useState('')
    const [submitting, setSubmitting] = useState(false)
    const [error, setError] = useState<string | null>(null)

    useEffect(() => {
        if (!token) { setTokenState('invalid'); return }
        let cancelled = false
        fetch(`/api/auth/setup-owner?token=${encodeURIComponent(token)}`)
            .then((res) => res.json())
            .then((data) => {
                if (cancelled) return
                if (data?.valid) {
                    setOrgName(data.organization_name || '')
                    setTokenState('valid')
                } else {
                    setTokenState('invalid')
                }
            })
            .catch(() => { if (!cancelled) setTokenState('invalid') })
        return () => { cancelled = true }
    }, [token])

    async function handleSubmit(e: React.FormEvent) {
        e.preventDefault()
        setError(null)

        if (password.length < 8) { setError('A senha precisa ter pelo menos 8 caracteres.'); return }
        if (password !== confirmPassword) { setError('As senhas não coincidem.'); return }

        setSubmitting(true)
        try {
            const res = await fetch('/api/auth/setup-owner', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ setup_token: token, full_name: fullName, email, password }),
            })
            const data = await res.json()
            if (!res.ok) {
                setError(data?.error || 'Não foi possível ativar sua conta.')
                return
            }

            const result = await signIn('credentials', {
                email: email.toLowerCase().trim(),
                password,
                redirect: false,
            })
            if (result?.error) {
                setError('Conta criada, mas não foi possível entrar automaticamente. Faça login.')
                router.push('/login')
                return
            }

            router.push('/')
            router.refresh()
        } catch (err) {
            setError('Ocorreu um erro. Tente novamente.')
        } finally {
            setSubmitting(false)
        }
    }

    if (tokenState === 'checking') {
        return (
            <div className="min-h-screen bg-void flex items-center justify-center p-4">
                <p className="text-muted text-sm">Verificando seu link de acesso...</p>
            </div>
        )
    }

    if (tokenState === 'invalid') {
        return (
            <div className="min-h-screen bg-void flex flex-col items-center justify-center p-4 text-center">
                <h1 className="text-xl font-bold text-ink mb-2">Link inválido ou expirado</h1>
                <p className="text-muted text-sm max-w-sm">
                    Peça pra quem te enviou o acesso gerar um novo link, ou entre em contato com o suporte.
                </p>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-void relative overflow-hidden flex flex-col items-center justify-center p-4">
            <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden="true">
                <div className="absolute -top-40 left-1/2 -translate-x-1/2 w-[700px] h-[700px] rounded-full bg-[radial-gradient(circle,rgba(242,199,68,0.14)_0%,transparent_70%)]" />
            </div>

            <div className="relative w-full max-w-sm">
                <div className="text-center mb-8">
                    <img
                        src="/logos/tita-logo.png"
                        alt="TitaCRM"
                        className="w-20 h-20 mx-auto mb-4 object-contain drop-shadow-[0_0_28px_rgba(242,199,68,0.35)]"
                    />
                    <h1 className="text-2xl font-light text-ink tracking-tight">Vamos ativar sua conta</h1>
                    {orgName && (
                        <p className="text-muted text-sm mt-1">
                            Workspace: <span className="font-semibold text-ink">{orgName}</span>
                        </p>
                    )}
                </div>

                <form onSubmit={handleSubmit} className="space-y-4 bg-panel border border-line rounded-2xl p-6">
                    {error && (
                        <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-lg px-4 py-3">
                            {error}
                        </div>
                    )}

                    <div>
                        <label className="block text-sm font-medium text-ink mb-1">Nome completo</label>
                        <input
                            type="text"
                            value={fullName}
                            onChange={(e) => setFullName(e.target.value)}
                            required
                            autoComplete="name"
                            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                            placeholder="Seu nome"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-ink mb-1">Email</label>
                        <input
                            type="email"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            required
                            autoComplete="email"
                            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                            placeholder="seu@email.com"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-ink mb-1">Senha</label>
                        <input
                            type="password"
                            value={password}
                            onChange={(e) => setPassword(e.target.value)}
                            required
                            autoComplete="new-password"
                            minLength={8}
                            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                            placeholder="Mínimo de 8 caracteres"
                        />
                    </div>

                    <div>
                        <label className="block text-sm font-medium text-ink mb-1">Confirmar senha</label>
                        <input
                            type="password"
                            value={confirmPassword}
                            onChange={(e) => setConfirmPassword(e.target.value)}
                            required
                            autoComplete="new-password"
                            className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
                            placeholder="Repita a senha"
                        />
                    </div>

                    <button
                        type="submit"
                        disabled={submitting}
                        className="w-full bg-gradient-to-r from-[#4f8bff] to-[#2f6bf0] text-white font-semibold py-2.5 rounded-lg text-sm transition-all hover:shadow-glow disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                        {submitting ? 'Ativando...' : 'Ativar conta e entrar'}
                    </button>
                </form>
            </div>
        </div>
    )
}

export default function AtivarContaPage() {
    return (
        <Suspense fallback={
            <div className="min-h-screen bg-void flex items-center justify-center p-4">
                <p className="text-muted text-sm">Carregando...</p>
            </div>
        }>
            <AtivarContaForm />
        </Suspense>
    )
}
