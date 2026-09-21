/**
 * Helpers de autenticação para o lado do cliente
 * Substitui: supabase.auth.getSession(), supabase.auth.signInWithPassword(), etc.
 *
 * Usa next-auth/react no cliente e next-auth no servidor
 */
'use client'

import { signIn as nextAuthSignIn, signOut as nextAuthSignOut, useSession } from 'next-auth/react'

export async function signInWithPassword(email: string, password: string) {
  const result = await nextAuthSignIn('credentials', {
    email,
    password,
    redirect: false,
  })

  if (result?.error) {
    return { error: { message: 'Email ou senha inválidos.' } }
  }

  return { error: null }
}

export async function signOut() {
  await nextAuthSignOut({ callbackUrl: '/login' })
}

export { useSession }
