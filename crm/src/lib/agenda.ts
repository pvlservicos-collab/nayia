/**
 * Tudo que o CRM sabe sobre a agenda montada no site "Agenda em Ascensão".
 *
 * O site manda duas coisas dentro de `agenda`: as ~30 respostas do quiz (`a1`)
 * e a semana já montada bloco a bloco (`real`). Este arquivo é o único lugar
 * que entende esse formato — usado tanto na entrada (leadSources.ts, pra
 * derivar as colunas de resumo) quanto nas telas (planilha de leads e painel
 * do lead no chat).
 *
 * Fica separado de leadSources.ts porque nada aqui depende de fonte: são
 * funções puras sobre o JSON da agenda. Ter isso num módulo só evita a
 * armadilha de a planilha e o painel do lead formatarem o mesmo dado de dois
 * jeitos diferentes.
 */

export const AGENDA_WEEKDAYS = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom']

/** Rótulos legíveis das respostas do quiz (`agenda.a1`), na ordem de exibição. */
export const AGENDA_QUIZ_LABELS: { key: string; label: string; hint?: string }[] = [
  { key: 'bed', label: 'Vai dormir' },
  { key: 'wake', label: 'Acorda' },
  { key: 'ws', label: 'Início do expediente' },
  { key: 'we', label: 'Fim do expediente' },
  { key: 'wdays', label: 'Dias que trabalha', hint: '0=seg … 6=dom' },
  { key: 'commute', label: 'Deslocamento até o trabalho', hint: 'min por trecho (0 = trabalha em casa)' },
  { key: 'meetAM', label: 'Reunião de manhã', hint: 'minutos' },
  { key: 'meetPM', label: 'Reunião à tarde', hint: 'minutos' },
  { key: 'meetEve', label: 'Reunião à noite', hint: 'minutos' },
  { key: 'bfT', label: 'Café da manhã — horário' },
  { key: 'bfD', label: 'Café da manhã — duração' },
  { key: 'lunchT', label: 'Almoço — horário' },
  { key: 'lunchD', label: 'Almoço — duração' },
  { key: 'dinT', label: 'Jantar — horário' },
  { key: 'dinD', label: 'Jantar — duração' },
  { key: 'train', label: 'Treina atualmente' },
  { key: 'trainDays', label: 'Dias de treino' },
  { key: 'trainT', label: 'Treino — horário' },
  { key: 'trainD', label: 'Treino — duração' },
  { key: 'trainCom', label: 'Deslocamento até o treino', hint: 'min por trecho' },
  { key: 'ppl', label: 'Tem momentos fixos com pessoas importantes' },
  { key: 'pplWkDays', label: 'Pessoas (semana) — dias' },
  { key: 'pplWkT', label: 'Pessoas (semana) — horário' },
  { key: 'pplWkD', label: 'Pessoas (semana) — duração' },
  { key: 'pplWeDays', label: 'Pessoas (fim de semana) — dias' },
  { key: 'pplWeT', label: 'Pessoas (fim de semana) — horário' },
  { key: 'pplWeD', label: 'Pessoas (fim de semana) — duração' },
  { key: 'vazAM', label: 'Procrastinação de manhã', hint: 'minutos' },
  { key: 'vazAMp', label: 'Procrastinação de manhã — posição', hint: 'começo / fim' },
  { key: 'vazPM', label: 'Procrastinação à tarde', hint: 'minutos' },
  { key: 'vazPMp', label: 'Procrastinação à tarde — posição', hint: 'começo / fim' },
]

/**
 * Categorias de bloco da agenda montada (`agenda.real[].c`).
 *
 * `label` é o nome que a Agenda em Ascensão usa com o lead — é o vocabulário
 * dele, então é o que aparece na tela. `desc` explica o que cai ali, pra quem
 * está no CRM e não conhece os Faróis; vai no title do item e da legenda.
 */
export const AGENDA_BLOCK_CATEGORIES: Record<string, { label: string; desc: string; color: string }> = {
  f1: { label: 'Farol 1 · rumo às metas', desc: 'Trabalho e progresso financeiro direto', color: '#f2c744' },
  f2: { label: 'Farol 2 · ser a sua palavra', desc: 'Compromissos com outras pessoas — reuniões, calls', color: '#7aa2f7' },
  f3: { label: 'Farol 3 · autossustentável', desc: 'Rotina que mantém a pessoa funcionando', color: '#5fd39b' },
  sono: { label: 'Sono', desc: 'Sono', color: '#8b7ff5' },
  desvio: { label: 'Desvio de rota', desc: 'Necessário, mas fora dos Faróis — deslocamento, burocracia', color: '#9a9a94' },
  vaz: { label: 'Procrastinação', desc: 'Tempo perdido', color: '#e0705a' },
}

/** Um bloco da semana montada. `s`/`d` em minutos, `day` 0=seg … 6=dom. */
export interface AgendaBlock {
  id?: number
  /** Título do bloco ("Trabalho", "Treino"…). */
  t?: string
  /** Início, em minutos desde 00:00. */
  s?: number
  /** Duração em minutos. */
  d?: number
  /** Categoria — chave de AGENDA_BLOCK_CATEGORIES. */
  c?: string
  day?: number
}

/** O objeto `agenda` como o site manda. */
export interface AgendaPayload {
  uid?: number | null
  /** "done" = quiz completo com agenda pronta; "w1" = parou no meio. */
  phase?: string | null
  a1?: Record<string, unknown> | null
  real?: AgendaBlock[] | null
  instagram?: string | null
  area?: string | null
  aumento?: string | null
  investimento?: string | null
}

/**
 * O `a1` com que o site abre o questionário, antes de a pessoa tocar em nada.
 *
 * Copiado de `let S = {...}` no index.html da Agenda em Ascensão. Existe aqui
 * por um motivo só: o site salva o lead assim que ele digita nome e WhatsApp —
 * ou seja, antes de responder qualquer pergunta — e manda esse `a1` pré-
 * preenchido junto. Sem comparar contra ele, o CRM mostrava "dorme 23:00,
 * treina Seg/Qua/Sex 18:30, procrastina 1h30 de manhã" para quem não respondeu
 * absolutamente nada. Eram 58 leads exibindo o mesmo perfil inventado, e quem
 * fosse atender ligaria confiando nele.
 *
 * Se o site mudar esses padrões, esta cópia precisa mudar junto — o pior caso é
 * ela ficar velha e alguns leads voltarem a exibir valor de fábrica como
 * resposta; por isso o valor fica exposto, e não escondido numa função.
 */
export const AGENDA_A1_PADRAO: Record<string, unknown> = {
  bed: '23:00', wake: '07:00', ws: '09:00', we: '18:00', wdays: [0, 1, 2, 3, 4],
  commute: 15, meetAM: 60, meetPM: 60, meetEve: 0,
  lunchT: '12:00', lunchD: 60, bfT: '07:00', bfD: 30, dinT: '21:00', dinD: 60,
  train: true, trainDays: [0, 2, 4], trainT: '18:30', trainD: 60, trainCom: 15,
  ppl: true, pplWkDays: [0, 1, 2, 3, 4], pplWkT: '20:00', pplWkD: 180,
  pplWeDays: [5, 6], pplWeT: '11:00', pplWeD: 420,
  vazAM: 90, vazAMp: 'começo', vazPM: 90, vazPMp: 'começo',
}

/**
 * As respostas são só o padrão do site — a pessoa não respondeu ao questionário.
 *
 * Exige que os 31 campos estejam intactos: quem mexeu em um já estava
 * respondendo, e aí o resto (que ficou no padrão) é escolha dele, não invenção
 * nossa. Quem concluiu (`phase === 'done'`) também fica de fora, mesmo com tudo
 * no padrão: clicar "próximo" por todas as etapas e montar a agenda é aceitar
 * aqueles valores, e nesse caso existe uma semana montada de verdade pra provar.
 */
export function quizNaoRespondido(a1: Record<string, any> | null | undefined, phase?: string | null): boolean {
  if (!a1 || typeof a1 !== 'object') return false
  if (phase === 'done') return false
  return Object.entries(AGENDA_A1_PADRAO).every(
    ([chave, valor]) => JSON.stringify(a1[chave]) === JSON.stringify(valor)
  )
}

/* ── Formatação ───────────────────────────────────────────────────────────── */

/** Minutos desde 00:00 → "08:30". */
export function minutesToClock(minutes: number): string {
  const normalized = ((minutes % 1440) + 1440) % 1440
  const h = Math.floor(normalized / 60)
  const m = normalized % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
}

/** 90 → "1h30", 45 → "45min". */
export function formatDuration(minutes: number): string {
  const total = Number(minutes) || 0
  if (total < 60) return `${total}min`
  const h = Math.floor(total / 60)
  const m = total % 60
  return m === 0 ? `${h}h` : `${h}h${String(m).padStart(2, '0')}`
}

/** [0,1,4] → "Seg,Ter,Sex". Índices fora da semana viram "?". */
export function formatWeekdays(value: unknown): string {
  if (!Array.isArray(value) || value.length === 0) return '—'
  return value
    .slice()
    .sort((a, b) => Number(a) - Number(b))
    .map((i) => AGENDA_WEEKDAYS[Number(i)] ?? '?')
    .join(',')
}

/** Os valores do quiz vêm em tipos variados (número, bool, lista de dias). */
export function formatQuizValue(key: string, value: unknown): string {
  if (value === null || value === undefined || value === '') return '—'
  if (typeof value === 'boolean') return value ? 'Sim' : 'Não'
  if (Array.isArray(value)) {
    if (value.length === 0) return '—'
    // Listas de dias vêm como índices 0=seg … 6=dom.
    if (/days$/i.test(key)) return formatWeekdays(value)
    return value.join(', ')
  }
  return String(value)
}

/** Blocos agrupados por dia da semana, cada dia em ordem cronológica. */
export function groupBlocksByDay(blocks: AgendaBlock[]) {
  return AGENDA_WEEKDAYS.map((label, day) => ({
    label,
    day,
    items: blocks
      .filter((b) => Number(b.day) === day)
      .sort((a, b) => (a.s ?? 0) - (b.s ?? 0)),
  })).filter((d) => d.items.length > 0)
}

/* ── Resumo em texto ──────────────────────────────────────────────────────── */

/**
 * As respostas do quiz condensadas nas mesmas frases que a exportação do site
 * gera ("22:00–05:00", "Seg,Ter,Qua 05:45 (2h)").
 *
 * É o que alimenta as colunas da planilha: `a1` cru tem 31 campos e nenhum
 * deles cabe numa célula. As regras são as mesmas de `api/admin/leads-export.js`
 * no repositório da Agenda — de propósito, pra que o lead importado por
 * planilha e o lead que chegou pelo webhook mostrem exatamente o mesmo texto na
 * mesma coluna.
 */
export function resumoAgenda(a1: Record<string, any> | null | undefined): Record<string, string> {
  if (!a1 || typeof a1 !== 'object') return {}

  const resumo: Record<string, string> = {}
  const põe = (chave: string, valor: string) => {
    if (valor && valor !== '—') resumo[chave] = valor
  }

  põe('sono', a1.bed && a1.wake ? `${a1.bed}–${a1.wake}` : '—')
  põe('trabalho', a1.ws && a1.we ? `${a1.ws}–${a1.we} (${formatWeekdays(a1.wdays)})` : '—')
  põe('deslocamento', a1.commute ? `${formatDuration(a1.commute)}/trecho` : '—')

  const reunioes: string[] = []
  if (Number(a1.meetAM) > 0) reunioes.push(`manhã ${formatDuration(a1.meetAM)}`)
  if (Number(a1.meetPM) > 0) reunioes.push(`tarde ${formatDuration(a1.meetPM)}`)
  if (Number(a1.meetEve) > 0) reunioes.push(`noite ${formatDuration(a1.meetEve)}`)
  põe('reunioes', reunioes.join(', '))

  const refeicao = (hora: unknown, dur: unknown) => (hora ? `${hora} (${formatDuration(dur as number)})` : '—')
  põe('cafe', refeicao(a1.bfT, a1.bfD))
  põe('almoco', refeicao(a1.lunchT, a1.lunchD))
  põe('jantar', refeicao(a1.dinT, a1.dinD))

  // "Não" é resposta, não ausência: quem não treina precisa aparecer como quem
  // não treina, e não como célula vazia.
  resumo.treino = a1.train
    ? `${formatWeekdays(a1.trainDays)} ${a1.trainT ?? ''} (${formatDuration(a1.trainD)})`.trim()
    : 'Não'

  if (!a1.ppl) {
    resumo.pessoas = 'Não'
  } else {
    const pessoas: string[] = []
    if (Array.isArray(a1.pplWkDays) && a1.pplWkDays.length) {
      pessoas.push(`${formatWeekdays(a1.pplWkDays)} ${a1.pplWkT ?? ''}`.trim())
    }
    if (Array.isArray(a1.pplWeDays) && a1.pplWeDays.length) {
      pessoas.push(`${formatWeekdays(a1.pplWeDays)} ${a1.pplWeT ?? ''}`.trim())
    }
    resumo.pessoas = pessoas.length ? pessoas.join(' / ') : 'Sim'
  }

  const procrastinacao: string[] = []
  if (Number(a1.vazAM) > 0) procrastinacao.push(`manhã ${formatDuration(a1.vazAM)}`)
  if (Number(a1.vazPM) > 0) procrastinacao.push(`tarde ${formatDuration(a1.vazPM)}`)
  põe('procrastinacao', procrastinacao.join(', '))

  return resumo
}
