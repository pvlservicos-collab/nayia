/**
 * O LEMBRETE DA VISITA (Pedro, 01/10/2026): "posso adicionar um lembrete ali
 * mesmo, igual esse lembrete de mensagem... por padrão o lembrete já vem
 * configurado para 1 hora antes".
 *
 * É um follow-up agendado (drizzle 0131/0132) que sabe de qual visita é e
 * quanto antes dela sai. Por isso ele SEGUE a visita: excluída na agenda, o
 * lembrete que ainda não saiu é cancelado; mudou de horário, ele vai junto.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'

export const LEMBRETE_PADRAO_MIN = 60

// o texto (modelo, marcas, "hoje às 15:00") mora em lembreteDaVisitaTexto.ts, sem banco: a tela também usa
export { MODELO_DO_LEMBRETE, preencherLembrete, primeiroNome, quandoNoLembrete, textoDoLembrete } from '@/lib/lembreteDaVisitaTexto'

export async function agendarLembreteDaVisita(p: {
  organizacao: string; leadId: string; visita: number; minutosAntes: number; mensagem: string
  enviarEm: Date; criadoPor: string; criadoPorNome: string | null
}): Promise<void> {
  await db.execute(sql`
    INSERT INTO followups_agendados (organization_id, lead_id, mensagem, enviar_em, criado_por, criado_por_nome, visita_id, minutos_antes)
    VALUES (${p.organizacao}::uuid, ${p.leadId}::uuid, ${p.mensagem}, ${p.enviarEm.toISOString()}::timestamptz,
            ${p.criadoPor}::uuid, ${p.criadoPorNome}, ${p.visita}, ${p.minutosAntes})`)
}

/** A visita saiu da agenda: o lembrete que ainda não saiu não sai mais. */
export async function cancelarLembretesDaVisita(visita: number): Promise<number> {
  const r = await db.execute(sql`
    UPDATE followups_agendados SET estado = 'cancelado'
     WHERE visita_id = ${visita} AND estado = 'agendado' RETURNING id`)
  return r.rows.length
}

/**
 * A visita mudou de horário: o lembrete vai junto. Se o novo horário do
 * lembrete já passou, ele é cancelado -- mandar "lembrete" atrasado de uma
 * visita que já está acontecendo só confunde.
 */
export async function moverLembretesDaVisita(visita: number, quando: Date): Promise<{ movidos: number; cancelados: number }> {
  const movidos = await db.execute(sql`
    UPDATE followups_agendados
       SET enviar_em = ${quando.toISOString()}::timestamptz - make_interval(mins => coalesce(minutos_antes, ${LEMBRETE_PADRAO_MIN}))
     WHERE visita_id = ${visita} AND estado = 'agendado'
       AND ${quando.toISOString()}::timestamptz - make_interval(mins => coalesce(minutos_antes, ${LEMBRETE_PADRAO_MIN})) > now() + interval '1 minute'
    RETURNING id`)
  const cancelados = await db.execute(sql`
    UPDATE followups_agendados SET estado = 'cancelado'
     WHERE visita_id = ${visita} AND estado = 'agendado'
       AND ${quando.toISOString()}::timestamptz - make_interval(mins => coalesce(minutos_antes, ${LEMBRETE_PADRAO_MIN})) <= now() + interval '1 minute'
    RETURNING id`)
  return { movidos: movidos.rows.length, cancelados: cancelados.rows.length }
}
