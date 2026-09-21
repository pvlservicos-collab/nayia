'use client'

/**
 * A agenda do lead dentro do painel de informações (chat e Pipeline).
 *
 * Quem preencheu o quiz da Agenda em Ascensão mandou ~30 respostas e uma semana
 * inteira montada bloco a bloco. Isso ficava só na planilha de /leads, numa
 * outra tela — quem estava atendendo a pessoa no chat não via nada disso. Aqui
 * é o mesmo dado, no lugar onde a conversa acontece.
 *
 * Os dados vêm de GET /api/leads/{id}/submissions, que devolve o que cada fonte
 * mandou sobre este lead. Serve tanto a lista antiga quanto o webhook do site:
 * as duas guardam o quiz no mesmo formato.
 */

import { useState, useEffect } from 'react'
import { CalendarBlank, CaretDown, CaretRight } from '@phosphor-icons/react'
import {
  AGENDA_BLOCK_CATEGORIES,
  AGENDA_QUIZ_LABELS,
  formatQuizValue,
  quizNaoRespondido,
  type AgendaBlock,
} from '@/lib/agenda'
import AgendaGrid from '@/components/Shared/AgendaGrid'

interface LeadSubmission {
  id: string
  source: string
  source_label: string
  external_id: string | null
  instagram: string | null
  payload: Record<string, any>
  received_at: string
  updated_at: string
}

/** Campos de resumo do quiz, na ordem em que fazem sentido lidos em sequência. */
const RESUMO: { key: string; label: string }[] = [
  { key: 'sono', label: 'Sono' },
  { key: 'trabalho', label: 'Trabalho' },
  { key: 'deslocamento', label: 'Deslocamento' },
  { key: 'reunioes', label: 'Reuniões' },
  { key: 'cafe', label: 'Café da manhã' },
  { key: 'almoco', label: 'Almoço' },
  { key: 'jantar', label: 'Jantar' },
  { key: 'treino', label: 'Treino' },
  { key: 'pessoas', label: 'Pessoas importantes' },
  { key: 'procrastinacao', label: 'Procrastinação' },
]

const PERFIL: { key: string; label: string }[] = [
  { key: 'area', label: 'Área de atuação' },
  { key: 'aumento', label: 'Aumento esperado (6m)' },
  { key: 'investimento', label: 'Já investiu' },
]

/** Tem alguma coisa da Agenda aqui dentro? */
function temAgenda(payload: Record<string, any>): boolean {
  if (!payload) return false
  if (payload.a1 || (Array.isArray(payload.real) && payload.real.length > 0)) return true
  return RESUMO.some(({ key }) => payload[key]) || PERFIL.some(({ key }) => payload[key])
}

export default function LeadAgendaCard({ leadId }: { leadId: string }) {
  const [submissions, setSubmissions] = useState<LeadSubmission[]>([])
  const [loading, setLoading] = useState(true)
  const [abertos, setAbertos] = useState<Set<string>>(new Set())

  useEffect(() => {
    let cancelado = false
    setLoading(true)
    fetch(`/api/leads/${leadId}/submissions`)
      .then((res) => (res.ok ? res.json() : { data: [] }))
      .then(({ data }) => {
        if (cancelado) return
        const comAgenda = (data || []).filter((s: LeadSubmission) => temAgenda(s.payload))
        setSubmissions(comAgenda)
        // A semana já abre desenhada: quem clica no lead quer ver a agenda dele,
        // e a grade atrás de mais um clique fazia o painel parecer só texto.
        // O quiz continua fechado — são 31 respostas, é consulta, não é o
        // primeiro olhar.
        setAbertos(new Set(comAgenda.map((s: LeadSubmission) => `${s.id}:semana`)))
      })
      .catch(() => {
        if (!cancelado) setSubmissions([])
      })
      .finally(() => {
        if (!cancelado) setLoading(false)
      })
    return () => {
      cancelado = true
    }
  }, [leadId])

  // Enquanto carrega, e quando o lead não veio da Agenda, o cartão não aparece:
  // a maioria dos leads não tem agenda, e um cartão vazio em todo painel só
  // empurraria o resto pra baixo.
  if (loading || submissions.length === 0) return null

  const alternar = (chave: string) =>
    setAbertos((atual) => {
      const novo = new Set(atual)
      if (novo.has(chave)) novo.delete(chave)
      else novo.add(chave)
      return novo
    })

  return (
    <div className="glass-soft rounded-xl p-3 space-y-3">
      <div className="flex items-center gap-1.5">
        <CalendarBlank size={13} className="text-[var(--chat-accent)]" weight="bold" />
        <p className="text-[11px] font-bold text-[var(--chat-text-secondary)]">Agenda em Ascensão</p>
      </div>

      {submissions.map((submission) => {
        const payload = submission.payload || {}
        const quiz = (payload.a1 ?? null) as Record<string, unknown> | null
        const blocks = (Array.isArray(payload.real) ? payload.real : []) as AgendaBlock[]
        const fase = (payload.phase ?? payload.fase ?? null) as string | null
        // `quiz_padrao` vem gravado desde a ingestão; o quizNaoRespondido()
        // cobre as linhas que entraram antes dessa checagem existir, sem
        // depender de alguém rodar a ressincronização pra parar de mentir.
        const semResposta = payload.quiz_padrao === true || quizNaoRespondido(quiz, fase)

        const chaveQuiz = `${submission.id}:quiz`
        const chaveSemana = `${submission.id}:semana`

        return (
          <div key={submission.id} className="space-y-2.5">
            <div className="flex items-center justify-between gap-2">
              <p className="text-[10px] uppercase tracking-wider font-bold text-[var(--chat-text-tertiary)]">
                {submission.source_label}
                {submission.external_id ? ` · #${submission.external_id}` : ''}
              </p>
              <span
                className={`text-[10px] px-1.5 py-0.5 rounded-full border ${
                  fase === 'done'
                    ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-400'
                    : 'border-[var(--chat-border)] text-[var(--chat-text-tertiary)]'
                }`}
              >
                {fase === 'done' ? 'Quiz completo' : fase === 'w1' ? 'Quiz incompleto' : 'Quiz —'}
              </span>
            </div>

            {/* Perfil profissional + resumo do quiz: as respostas em uma linha
                cada, que é o que dá pra ler de relance antes de falar com a
                pessoa. O detalhe fica nas seções que abrem abaixo. */}
            <dl className="space-y-1.5">
              {[...PERFIL, ...(semResposta ? [] : RESUMO)].map(({ key, label }) =>
                payload[key] ? (
                  <div key={key} className="flex items-baseline justify-between gap-3">
                    <dt className="text-[11px] text-[var(--chat-text-tertiary)] flex-shrink-0">{label}</dt>
                    <dd className="text-[11px] text-[var(--chat-text-secondary)] text-right break-words min-w-0">
                      {String(payload[key])}
                    </dd>
                  </div>
                ) : null
              )}
            </dl>

            {blocks.length > 0 && (
              <div>
                <button
                  onClick={() => alternar(chaveSemana)}
                  className="w-full flex items-center gap-1 text-[11px] font-bold text-[var(--chat-text-secondary)] hover:text-[var(--chat-accent)] transition-colors"
                >
                  {abertos.has(chaveSemana) ? <CaretDown size={11} weight="bold" /> : <CaretRight size={11} weight="bold" />}
                  Semana montada
                  <span className="font-medium text-[var(--chat-text-tertiary)]">({blocks.length} blocos)</span>
                </button>

                {abertos.has(chaveSemana) && (
                  <div className="mt-2 space-y-2">
                    {/* 460 porque a 21px/hora um dia inteiro dá ~500px: quase toda semana
                        cabe sem rolar, que era o ponto de encolher a escala. */}
                    <AgendaGrid blocks={blocks} alturaMax={460} />
                    <div className="flex flex-wrap gap-x-3 gap-y-1">
                      {Object.entries(AGENDA_BLOCK_CATEGORIES).map(([chave, meta]) => (
                        <span
                          key={chave}
                          title={meta.desc}
                          className="flex items-center gap-1 text-[9.5px] text-[var(--chat-text-tertiary)]"
                        >
                          <span
                            className="w-2 h-2 rounded-full flex-shrink-0"
                            style={{ backgroundColor: meta.color }}
                          />
                          {meta.label}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}

            {semResposta && (
              <p className="text-[11px] text-[var(--chat-text-tertiary)]">
                Deixou nome e WhatsApp e saiu antes de responder — o questionário
                está todo no valor padrão do site.
              </p>
            )}

            {quiz && !semResposta && (
              <div>
                <button
                  onClick={() => alternar(chaveQuiz)}
                  className="w-full flex items-center gap-1 text-[11px] font-bold text-[var(--chat-text-secondary)] hover:text-[var(--chat-accent)] transition-colors"
                >
                  {abertos.has(chaveQuiz) ? <CaretDown size={11} weight="bold" /> : <CaretRight size={11} weight="bold" />}
                  Respostas do quiz
                </button>

                {abertos.has(chaveQuiz) && (
                  <dl className="mt-2 space-y-1.5">
                    {AGENDA_QUIZ_LABELS.map(({ key, label }) => (
                      <div key={key} className="flex items-baseline justify-between gap-3">
                        <dt className="text-[11px] text-[var(--chat-text-tertiary)] flex-shrink-0">{label}</dt>
                        <dd className="text-[11px] text-[var(--chat-text-secondary)] text-right break-words min-w-0">
                          {formatQuizValue(key, quiz[key])}
                        </dd>
                      </div>
                    ))}
                  </dl>
                )}
              </div>
            )}

            {/* Quando o lead veio pela Agenda mas o quiz parou no meio, dizer
                isso vale mais que deixar o cartão pela metade sem explicação. */}
            {blocks.length === 0 && !semResposta && (
              <p className="text-[11px] text-[var(--chat-text-tertiary)]">
                Sem semana montada — a pessoa não terminou o quiz no site.
              </p>
            )}
          </div>
        )
      })}
    </div>
  )
}
