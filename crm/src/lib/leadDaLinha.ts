/**
 * UM LEAD POR PESSOA EM CADA LINHA (Tel, 28/09/2026): "São 3 WhatsApp, cada um
 * em uma tab lá no CRM... preciso das 3 lá funcionais, e não misturando
 * contatos".
 *
 * Até aqui o lead era UM por telefone, e a mensagem que chegava por qualquer
 * número achava esse lead e o PUXAVA para a sua linha (`integration_id`). A
 * conversa do Tel pulava de aba a cada mensagem -- 279 mensagens da Parceria,
 * 15 da API oficial e 8 da captação no mesmo lead -- e a resposta saía pelo
 * número da última mensagem, não pelo da aba em que ele estava olhando.
 *
 * Agora quem acha o lead é sempre (telefone, linha):
 *
 *   1. o lead desta linha, se existe;
 *   2. senão, o lead SEM linha nenhuma (cadastro à mão, Agenda, site) é
 *      ADOTADO por esta linha -- é o mesmo contato, que só não tinha número;
 *   3. senão, nada: quem chamou cria o lead desta linha.
 *
 * O índice leads_org_phone_unique passou a ser (organização, telefone, linha)
 * com NULLS NOT DISTINCT (ver drizzle/0125): duas linhas, dois leads; sem
 * linha, um só.
 */
import { and, desc, eq, inArray, isNull } from 'drizzle-orm'
import { db } from './db'
import { integrations, leads } from './schema'
import { isUniqueViolation } from './db-helpers'

export type LeadDaLinha = typeof leads.$inferSelect

/**
 * O lead desta pessoa nesta linha (ou o sem linha, que passa a ser desta).
 *
 * `integrationId` null = quem chamou não sabe a linha (um link antigo por
 * telefone, por exemplo): devolve a conversa mais recente da pessoa, em
 * qualquer linha, sem adotar nada.
 */
export async function acharLeadDaLinha(
  organizationId: string,
  telefones: string[],
  integrationId: string | null,
): Promise<LeadDaLinha | null> {
  const formas = [...new Set(telefones.filter(Boolean))]
  if (formas.length === 0) return null
  const daPessoa = [
    eq(leads.organizationId, organizationId),
    inArray(leads.phone, formas),
    isNull(leads.deletedAt),
  ]

  if (!integrationId) {
    const [maisRecente] = await db.select().from(leads)
      .where(and(...daPessoa))
      .orderBy(desc(leads.lastActivityAt))
      .limit(1)
    return maisRecente ?? null
  }

  const [desta] = await db.select().from(leads)
    .where(and(...daPessoa, eq(leads.integrationId, integrationId)))
    .limit(1)
  if (desta) return desta

  const [semLinha] = await db.select().from(leads)
    .where(and(...daPessoa, isNull(leads.integrationId)))
    .limit(1)
  if (!semLinha) return null

  try {
    // `isNull` de novo no WHERE: se outra requisição adotou este lead para
    // outra linha no meio do caminho, esta não o rouba de volta.
    const [adotado] = await db.update(leads)
      .set({ integrationId })
      .where(and(eq(leads.id, semLinha.id), isNull(leads.integrationId)))
      .returning()
    if (adotado) return adotado
  } catch (err) {
    // Outra requisição criou o lead desta linha enquanto isto adotava o sem
    // linha: o índice único barra a adoção, e vale o que já existe.
    if (!isUniqueViolation(err)) throw err
  }
  const [corrida] = await db.select().from(leads)
    .where(and(...daPessoa, eq(leads.integrationId, integrationId)))
    .limit(1)
  return corrida ?? null
}

/** O id da integração ativa de um tipo (a linha), ou null se não existe. */
export async function integracaoDoTipo(organizationId: string, tipo: string): Promise<string | null> {
  const [integ] = await db.select({ id: integrations.id }).from(integrations)
    .where(and(
      eq(integrations.organizationId, organizationId),
      eq(integrations.type, tipo),
      isNull(integrations.deletedAt),
    ))
    .limit(1)
  return integ?.id ?? null
}
