/**
 * Em que momento da jornada o lead está — o que a Agenda Titã já sabe sobre ele.
 *
 * `w1` e `done` são os valores que a própria Agenda manda (o quiz parou no meio
 * ou foi até o fim), e por isso são reaproveitados aqui em vez de inventar
 * nomes novos: um lead cadastrado à mão como "gerou a agenda" fica idêntico a
 * um que veio pelo site. Os dois momentos da mentoria ainda não chegam
 * sozinhos — hoje quem sabe é quem atende, e digita.
 *
 * Guardado no mesmo campo `phase`/`fase` que a Agenda usa, e não num campo
 * paralelo: são a mesma pergunta ("até onde essa pessoa foi?"), e dois campos
 * para a mesma pergunta acabam divergindo.
 */

export interface Momento {
  key: string
  /** Rótulo curto — cabe numa etiqueta de tabela. */
  label: string
  /** O que significa, para quem está cadastrando. */
  descricao: string
  cor: string
}

export const MOMENTOS: Momento[] = [
  {
    key: 'w1',
    label: 'Só se cadastrou',
    descricao: 'Começou a agenda e parou no meio',
    cor: '#7b7b76',
  },
  {
    key: 'done',
    label: 'Gerou a agenda',
    descricao: 'Terminou o quiz e a agenda foi montada',
    cor: '#c98500',
  },
  {
    key: 'mentoria_iniciada',
    label: 'Começou a mentoria',
    descricao: 'Iniciou o cadastro na mentoria',
    cor: '#3987e5',
  },
  {
    key: 'mentoria_concluida',
    label: 'Concluiu a mentoria',
    descricao: 'Terminou o cadastro na mentoria',
    cor: '#3aa76d',
  },
]

export const MOMENTO_PADRAO = 'w1'

export function momentoPorChave(valor: unknown): Momento | undefined {
  return typeof valor === 'string' ? MOMENTOS.find((m) => m.key === valor) : undefined
}
