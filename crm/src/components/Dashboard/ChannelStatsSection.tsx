import { ShareNetwork } from '@phosphor-icons/react'
import GlassCard, { SectionHeader } from './GlassCard'
import { CHANNEL_META, CHANNEL_ORDER, type ChannelTotals } from './mockData'

interface ChannelStatsSectionProps {
  totals: ChannelTotals[]
}

export default function ChannelStatsSection({ totals }: ChannelStatsSectionProps) {
  const totalsByChannel = Object.fromEntries(totals.map(t => [t.channel, t.newCustomers]))
  const grandTotal = totals.reduce((sum, t) => sum + t.newCustomers, 0)

  return (
    <section>
      <div className="flex items-end justify-between mb-4">
        <SectionHeader
          icon={<ShareNetwork size={16} weight="bold" />}
          title="Canais de aquisição totais"
          subtitle="Clientes novos por canal"
        />
        <div className="text-right pb-1">
          <p className="text-2xl font-bold text-ink leading-none">{grandTotal.toLocaleString('pt-BR')}</p>
          <p className="text-[11px] text-muted mt-1">total no período</p>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4">
        {CHANNEL_ORDER.map(channel => {
          const meta = CHANNEL_META[channel]
          const value = totalsByChannel[channel] ?? 0
          const share = grandTotal > 0 ? Math.round((value / grandTotal) * 100) : 0
          return (
            <GlassCard key={channel} className="p-4">
              <div className="flex items-center gap-2 mb-3">
                <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: meta.color }} />
                <p className="text-xs font-medium text-muted truncate">{meta.label}</p>
              </div>
              <p className="text-2xl font-bold text-ink leading-none">{value.toLocaleString('pt-BR')}</p>
              <p className="text-[11px] text-muted mt-1.5">{share}% do total</p>
            </GlassCard>
          )
        })}
      </div>
    </section>
  )
}
