import type { NextAuthConfig } from 'next-auth'

export const authConfig: NextAuthConfig = {
  // Necessário fora da Vercel (que habilita isso sozinha via env VERCEL=1) — atrás de
  // um reverse proxy próprio (Traefik na VPS), sem isso o NextAuth rejeita o host com
  // erro "Configuration" antes mesmo de chegar no provider.
  trustHost: true,
  pages: {
    signIn: '/login',
    error: '/login',
  },
  session: { strategy: 'jwt' },
  callbacks: {
    jwt({ token, user }) {
      if (user) {
        token.id = user.id
        token.isSuperadmin = (user as any).isSuperadmin || false
      }
      return token
    },
    session({ session, token }) {
      if (session.user) {
        session.user.id = token.id as string
        ;(session.user as any).isSuperadmin = token.isSuperadmin as boolean
      }
      return session
    },
  },
  providers: [],
}
