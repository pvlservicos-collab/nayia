'use client'

/**
 * Painel de detalhe de uma linha da planilha.
 *
 * A Agenda manda ~30 respostas de quiz e a agenda montada bloco a bloco — isso
 * não cabe em coluna (uma planilha de 40 colunas não se lê). Então a tabela
 * mostra o essencial e o resto vive aqui: quiz com rótulo legível e os blocos
 * agrupados por dia da semana.
 */

import { X, ArrowSquareOut } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'
import Link from 'next/link'
import {
  AGENDA_BLOCK_CATEGORIES,
  AGENDA_QUIZ_LABELS,
  formatQuizValue,
  quizNaoRespondido,
  type AgendaBlock,
} from '@/lib/agenda'
import AgendaGrid from '@/components/Shared/AgendaGrid'
import type { Submission } from './types'
import { instagramUrl } from './SubmissionsTable'

export default function SubmissionDetail({
  submission,
  sourceKey,
  onClose,
}: {
  submission: Submission
  sourceKey: string
  onClose: () => void
}) {
  const payload = submission.payload || {}
  const quiz = (payload.a1 ?? null) as Record<string, unknown> | null
  const blocks = (Array.isArray(payload.real) ? payload.real : []) as AgendaBlock[]
  // As duas fontes da Agenda trazem perfil e quiz; muda so por onde o lead entrou.
  const isAgenda = sourceKey === 'agenda_ascensao' || sourceKey === 'agenda_antigos'
  const phase = (payload.phase ?? payload.fase ?? null) as string | null
  // Quiz inteiro no valor de fábrica do site = a pessoa não respondeu nada.
  const semResposta = payload.quiz_padrao === true || quizNaoRespondido(quiz, phase)


  return (
    <div className="fixed inset-0 z-[80] flex justify-end" role="dialog" aria-modal="true">
      <div className="absolute inset-0 bg-black/55 backdrop-blur-sm" onClick={onClose} />

      <div className="glass-raised relative z-10 h-full w-full max-w-xl rounded-none border-y-0 border-r-0 flex flex-col animate-in slide-in-from-right duration-200">
        <div className="relative flex items-start justify-between gap-3 px-5 py-4 flex-shrink-0">
          <div className="min-w-0">
            <h2 className="text-lg font-bold text-ink truncate">{submission.name || 'Sem nome'}</h2>
            <p className="text-xs text-muted mt-0.5">
              {submission.external_id ? `ID ${submission.external_id} · ` : ''}
              Recebido em {new Date(submission.received_at).toLocaleString('pt-BR')}
            </p>
          </div>
          <button onClick={onClose} className="btn-icon w-9 h-9 flex-shrink-0" aria-label="Fechar">
            <X size={18} />
          </button>
          <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-6 scrollbar-hide">
          {/* Contato */}
          <section>
            <h3 className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2.5">Contato</h3>
            <dl className="panel rounded-xl divide-y divide-white/5">
              <Row label="WhatsApp" value={submission.phone} />
              <Row label="E-mail" value={submission.email} />
              <Row
                label="Instagram"
                value={submission.instagram}
                href={submission.instagram ? instagramUrl(submission.instagram) : undefined}
              />
            </dl>
            {submission.lead_id && (
              <Link
                href={linkDaConversa(submission.lead_id)}
                className="btn btn-outline btn-sm mt-3"
              >
                Abrir lead no CRM
                <ArrowSquareOut size={14} weight="bold" />
              </Link>
            )}
          </section>

          {/* Perfil profissional — só a Agenda tem esses campos */}
          {isAgenda && (
            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2.5">Perfil</h3>
              <dl className="panel rounded-xl divide-y divide-white/5">
                <Row label="Área de atuação" value={payload.area as string} />
                <Row label="Aumento esperado em 6 meses" value={payload.aumento as string} />
                <Row label="Já investiu em cursos/mentorias" value={payload.investimento as string} />
                <Row
                  label="Quiz"
                  value={
                    phase === 'done'
                      ? 'Completo, com agenda montada'
                      : phase === 'w1'
                        ? 'Incompleto (parou no meio)'
                        : phase
                  }
                />
              </dl>
            </section>
          )}

          {semResposta && (
            <section>
              <div className="panel rounded-xl px-3.5 py-2.5">
                <p className="text-xs text-muted">
                  Deixou nome e WhatsApp e saiu antes de responder. O questionário
                  veio inteiro no valor padrão com que o site abre — por isso as
                  respostas não são mostradas: elas não são desta pessoa.
                </p>
              </div>
            </section>
          )}

          {/* Respostas do quiz */}
          {quiz && !semResposta && (
            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2.5">
                Respostas do quiz
              </h3>
              <dl className="panel rounded-xl divide-y divide-white/5">
                {AGENDA_QUIZ_LABELS.map(({ key, label, hint }) => (
                  <Row
                    key={key}
                    label={label}
                    hint={hint}
                    value={formatQuizValue(key, quiz[key])}
                  />
                ))}
              </dl>
            </section>
          )}

          {/* Agenda montada — a semana como ela aparece pro lead no site */}
          {blocks.length > 0 && (
            <section>
              <h3 className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2.5">
                Agenda montada
                <span className="ml-1.5 font-medium normal-case tracking-normal text-muted/70">
                  {blocks.length} blocos
                </span>
              </h3>

              <AgendaGrid blocks={blocks} alturaMax={520} />

              <div className="flex flex-wrap gap-x-4 gap-y-1.5 mt-3">
                {Object.entries(AGENDA_BLOCK_CATEGORIES).map(([key, meta]) => (
                  <span key={key} title={meta.desc} className="flex items-center gap-1.5 text-[11px] text-muted">
                    <span
                      className="w-2 h-2 rounded-full flex-shrink-0"
                      style={{ backgroundColor: meta.color }}
                    />
                    {meta.label}
                  </span>
                ))}
              </div>
            </section>
          )}

          {/* Escape hatch: se a fonte mandar um campo que a tela ainda não sabe
              exibir, ele continua visível aqui em vez de sumir. */}
          <section>
            <h3 className="text-[11px] font-bold uppercase tracking-wider text-muted mb-2.5">
              Payload recebido
            </h3>
            <pre className="glass-sunken rounded-xl p-3 text-[11px] text-muted overflow-x-auto leading-relaxed">
              {JSON.stringify(payload, null, 2)}
            </pre>
          </section>
        </div>
      </div>
    </div>
  )
}

function Row({
  label,
  value,
  hint,
  href,
}: {
  label: string
  value?: string | null
  hint?: string
  /** Quando presente, o valor vira link (abre em aba nova). */
  href?: string
}) {
  return (
    <div className="flex items-baseline justify-between gap-4 px-3.5 py-2.5">
      <dt className="text-xs text-muted flex-shrink-0">
        {label}
        {hint && <span className="block text-[10px] text-muted/60">{hint}</span>}
      </dt>
      <dd className="text-xs text-ink text-right break-words min-w-0">
        {value && href ? (
          <a
            href={href}
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-accent-2 underline decoration-dotted underline-offset-2 transition-colors"
          >
            {value}
          </a>
        ) : (
          value || '—'
        )}
      </dd>
    </div>
  )
}
