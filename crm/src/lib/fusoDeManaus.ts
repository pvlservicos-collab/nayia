/**
 * A HORA DO CRM É A DE MANAUS, não a do computador de quem usa.
 *
 * Pedro, 03/10/2026: "está com o horário de São Paulo na hora de agendar pelo card
 * do WhatsApp do corretor, e na agenda mesmo está horários de Manaus; pode colocar
 * os fusos tudo de Manaus?". A agenda já lia e gravava em Manaus (VisitasAgendadas,
 * AgendaDeVisitas). O formulário de agendar, o de follow-up e as etiquetas de
 * visita do card usavam `new Date('2026-10-04T10:00')` e `getHours()`: o relógio da
 * MÁQUINA. Com o computador em Brasília, "10:00" virava 09:00 de Manaus na agenda,
 * e a visita das 15:00 aparecia como 16:00 no card.
 *
 * Tudo o que agenda ou mostra hora de visita passa por aqui. Funções puras: rodam
 * na tela e no servidor.
 */
export const FUSO_DE_MANAUS = 'America/Manaus'
/** Manaus não tem horário de verão (desde 2000): o fuso é sempre -04:00. */
export const OFFSET_DE_MANAUS = '-04:00'

/** AAAA-MM-DD de um instante, no calendário de Manaus. */
export function diaEmManaus(d: Date = new Date()): string {
  return d.toLocaleDateString('en-CA', { timeZone: FUSO_DE_MANAUS })
}

/** AAAA-MM-DD de hoje + n dias, no calendário de Manaus ("hoje", "amanhã", "uma semana"). */
export function diaEmManausMais(n: number, agora: Date = new Date()): string {
  const [a, m, d] = diaEmManaus(agora).split('-').map(Number)
  return new Date(Date.UTC(a, m - 1, d + n)).toISOString().slice(0, 10)
}

/** HH:MM de um instante, no relógio de Manaus. */
export function horaEmManaus(d: Date): string {
  return d.toLocaleTimeString('en-GB', { timeZone: FUSO_DE_MANAUS, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
}

/** O instante de "dia às hora" DITO EM MANAUS (os campos de data e hora de um formulário). */
export function instanteEmManaus(dia: string, hora: string): Date {
  return new Date(`${dia}T${hora}:00${OFFSET_DE_MANAUS}`)
}

/** Quantos dias de calendário (de Manaus) separam o instante de hoje: 0 = hoje, 1 = amanhã, -1 = ontem. */
export function diasAteEmManaus(d: Date, agora: Date = new Date()): number {
  const dia = (x: Date) => { const [a, m, dd] = diaEmManaus(x).split('-').map(Number); return Date.UTC(a, m - 1, dd) }
  return Math.round((dia(d) - dia(agora)) / 86400000)
}

/** "04/10 10:00", em Manaus. */
export function dataHoraEmManaus(iso: string | Date | null | undefined, separador = ' '): string {
  if (!iso) return ''
  const d = typeof iso === 'string' ? new Date(iso) : iso
  if (Number.isNaN(d.getTime())) return ''
  return `${d.toLocaleDateString('pt-BR', { timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit' })}${separador}${horaEmManaus(d)}`
}

/** "hoje 15:00", "amanhã 09:30" ou "04/10 10:00", em Manaus (a etiqueta da visita no card e na lista). */
export function quandoCurtoEmManaus(iso: string | null | undefined, agora: Date = new Date()): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  const dif = diasAteEmManaus(d, agora)
  const h = horaEmManaus(d)
  return dif === 0 ? `hoje ${h}` : dif === 1 ? `amanhã ${h}` : `${d.toLocaleDateString('pt-BR', { timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit' })} ${h}`
}
