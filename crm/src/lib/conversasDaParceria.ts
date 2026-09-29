/**
 * As conversas da linha da Parceria (Z-API, 92 9445-3618), com o que a tela
 * precisa para ligar uma visita ou uma marca da Nay à conversa certa.
 */
import { and, eq, isNull } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations, leads } from '@/lib/schema'
import { chavesDaNay } from '@/lib/nayLeitura'

export interface ConversaDaParceria {
  id: string
  telefone: string | null
  titulo: string | null
  avatar: string | null
}

export async function conversasDaParceria(organizacao: string): Promise<ConversaDaParceria[]> {
  const linhas = await db
    .select({ id: leads.id, telefone: leads.phone, titulo: leads.title, avatar: leads.avatarUrl })
    .from(leads)
    .innerJoin(integrations, eq(integrations.id, leads.integrationId))
    .where(and(eq(leads.organizationId, organizacao), isNull(leads.deletedAt), eq(integrations.type, 'whatsapp_zapi')))
  return linhas
}

/** chave da Nay (55+DDD+8 ou lid:...) -> conversa do CRM */
export function conversaPorChave(conversas: ConversaDaParceria[]): Map<string, ConversaDaParceria> {
  const mapa = new Map<string, ConversaDaParceria>()
  for (const c of conversas) for (const ch of chavesDaNay(c.telefone)) if (!mapa.has(ch)) mapa.set(ch, c)
  return mapa
}
