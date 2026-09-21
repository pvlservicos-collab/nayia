/**
 * NextAuth route handler
 * Substitui Supabase Auth endpoints
 * Expõe: /api/auth/signin, /api/auth/signout, /api/auth/session, /api/auth/csrf
 */
import { handlers } from '@/lib/auth'
export const { GET, POST } = handlers
