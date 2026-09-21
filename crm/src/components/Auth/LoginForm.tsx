'use client'

/**
 * LoginForm — substitui Supabase signInWithPassword
 * Usa NextAuth Credentials provider
 */
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { signIn } from 'next-auth/react'

export default function LoginForm() {
  const router = useRouter()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError(null)

    try {
      const result = await signIn('credentials', {
        email: email.toLowerCase().trim(),
        password,
        redirect: false,
      })

      if (result?.error) {
        setError('Email ou senha inválidos.')
        return
      }

      // Redireciona direto para o chat após login
      router.push('/chat')
      router.refresh()
    } catch (err) {
      setError('Ocorreu um erro. Tente novamente.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4 w-full max-w-sm bg-panel border border-line rounded-2xl p-6">
      {error && (
        <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-lg px-4 py-3">
          {error}
        </div>
      )}

      <div>
        <label className="block text-sm font-medium text-ink mb-1">Usuário ou e-mail</label>
        <input
          // text, e nao email: o campo aceita usuario simples ("tita") alem de
          // e-mail. Com type="email" o proprio navegador barra o envio antes de
          // chegar no servidor. O authorize() do NextAuth compara a string como
          // ela veio (minusculas, sem espaco), entao os dois formatos funcionam.
          type="text"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          autoComplete="username"
          className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
          placeholder="tita ou seu@email.com"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-ink mb-1">Senha</label>
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          autoComplete="current-password"
          className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
          placeholder="••••••••"
        />
      </div>

      <button
        type="submit"
        disabled={loading}
        className="w-full bg-gradient-to-r from-[#4f8bff] to-[#2f6bf0] text-white font-semibold py-2.5 rounded-lg text-sm transition-all hover:shadow-glow disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {loading ? 'Entrando...' : 'Entrar'}
      </button>
    </form>
  )
}
