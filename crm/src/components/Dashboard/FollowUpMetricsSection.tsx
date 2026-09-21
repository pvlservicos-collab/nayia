import { Robot, ChatCircleText, ArrowsClockwise, ChatsCircle, Trophy } from '@phosphor-icons/react'
import GlassCard, { SectionHeader } from './GlassCard'
import { type FollowUpMetrics, type TopFollowUpMessage } from './mockData'

interface FollowUpMetricsSectionProps {
  metrics: FollowUpMetrics
  topMessages: TopFollowUpMessage[]
}

export default function FollowUpMetricsSection({
  metrics,
  topMessages,
}: FollowUpMetricsSectionProps) {
  const stats = [
    { key: 'initial', label: 'Contatos respondidos inicialmente', value: metrics.initialRepliesCount, icon: ChatCircleText },
    { key: 'sent', label: 'Follow ups realizados', value: metrics.followUpsSentCount, icon: ArrowsClockwise },
    { key: 'replied', label: 'Contatos que responderam os follow ups', value: metrics.followUpRepliesCount, icon: ChatsCircle },
  ]

  return (
    <section>
      <SectionHeader icon={<Robot size={16} weight="bold" />} title="Métricas da IA de follow up" />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4 mb-4">
        {stats.map(stat => {
          const Icon = stat.icon
          return (
            <GlassCard key={stat.key} className="p-4">
              <div className="flex items-center gap-2 mb-3">
                <Icon size={16} className="text-muted" weight="bold" />
                <p className="text-xs font-medium text-muted">{stat.label}</p>
              </div>
              <p className="text-2xl font-bold text-ink leading-none">{stat.value.toLocaleString('pt-BR')}</p>
            </GlassCard>
          )
        })}
      </div>

      <GlassCard className="p-4 sm:p-5">
        <div className="flex items-center gap-2 mb-4">
          <Trophy size={16} className="text-accent-2" weight="fill" />
          <p className="text-xs font-medium text-muted">Melhores mensagens de follow up</p>
        </div>
        {topMessages.length === 0 ? (
          <p className="text-xs text-muted py-3">
            Nenhum funil enviou mensagem ainda. Assim que um funil for ativado, os
            mais efetivos aparecem aqui.
          </p>
        ) : (
        <div className="space-y-2.5">
          {topMessages.map((msg, i) => (
            <div key={msg.id} className="glass-soft glass-hover flex items-center gap-3 rounded-2xl px-3.5 py-3">
              <span className="w-6 h-6 rounded-full bg-accent/15 border border-accent/25 text-accent-2 text-[11px] font-bold flex items-center justify-center flex-shrink-0">
                {i + 1}
              </span>
              <p className="flex-1 min-w-0 text-sm text-ink truncate">{msg.preview}</p>
              <div className="flex-shrink-0 text-right">
                <p className="text-sm font-bold text-accent-2 leading-none">{msg.responseRate}%</p>
                <p className="text-[10px] text-muted mt-0.5">{msg.sentCount} envios</p>
              </div>
            </div>
          ))}
        </div>
        )}
      </GlassCard>
    </section>
  )
}
