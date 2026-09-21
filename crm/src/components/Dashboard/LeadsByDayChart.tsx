'use client'

import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, TooltipContentProps } from 'recharts'
import { ChartLineUp } from '@phosphor-icons/react'
import GlassCard, { SectionHeader } from './GlassCard'
import { CHANNEL_META, CHANNEL_ORDER, type DailyLeadPoint } from './mockData'

const ACCENT = '#f2c744'

function formatDayLabel(iso: string) {
  const d = new Date(`${iso}T00:00:00`)
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

function CustomTooltip({ active, payload }: TooltipContentProps<any, any>) {
  if (!active || !payload || payload.length === 0) return null
  const point = payload[0].payload as DailyLeadPoint
  const total = CHANNEL_ORDER.reduce((sum, c) => sum + (point[c] ?? 0), 0)

  return (
    <div className="glass-raised rounded-xl px-3.5 py-3 min-w-[180px]">
      <div className="relative flex items-baseline justify-between gap-4 pb-2 mb-2">
        <span className="text-[11px] text-muted">{formatDayLabel(point.date)}</span>
        <span className="text-base font-bold text-ink">{total}</span>
        <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
      </div>
      <div className="space-y-1.5">
        {CHANNEL_ORDER.map(channel => {
          const meta = CHANNEL_META[channel]
          return (
            <div key={channel} className="flex items-center justify-between gap-4 text-xs">
              <span className="flex items-center gap-1.5 text-muted">
                <span className="w-2.5 h-0.5 rounded-full flex-shrink-0" style={{ backgroundColor: meta.color }} />
                {meta.label}
              </span>
              <span className="font-semibold text-ink">{point[channel] ?? 0}</span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

interface LeadsByDayChartProps {
  data: DailyLeadPoint[]
}

export default function LeadsByDayChart({ data }: LeadsByDayChartProps) {
  const chartData = data.map(p => ({
    ...p,
    total: CHANNEL_ORDER.reduce((sum, c) => sum + (p[c] ?? 0), 0),
  }))

  return (
    <GlassCard className="p-5">
      <SectionHeader
        icon={<ChartLineUp size={16} weight="bold" />}
        title="Recepção de leads por dia"
        subtitle="Total no período — passe o mouse para ver por canal"
      />
      <div className="h-64 -ml-2">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={chartData} margin={{ top: 8, right: 12, left: 0, bottom: 0 }}>
            <defs>
              <linearGradient id="leadsTotalFill" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={ACCENT} stopOpacity={0.28} />
                <stop offset="100%" stopColor={ACCENT} stopOpacity={0.02} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="rgba(255,255,255,0.07)" strokeDasharray="0" />
            <XAxis
              dataKey="date"
              tickFormatter={formatDayLabel}
              tick={{ fill: '#9a9a94', fontSize: 11 }}
              axisLine={{ stroke: 'rgba(255,255,255,0.12)' }}
              tickLine={false}
              minTickGap={20}
            />
            <YAxis
              tick={{ fill: '#9a9a94', fontSize: 11 }}
              axisLine={false}
              tickLine={false}
              width={28}
              allowDecimals={false}
            />
            <Tooltip content={(props) => <CustomTooltip {...props} />} cursor={{ stroke: 'rgba(255,255,255,0.18)', strokeWidth: 1 }} />
            <Area
              type="monotone"
              dataKey="total"
              stroke={ACCENT}
              strokeWidth={2}
              fill="url(#leadsTotalFill)"
              activeDot={{ r: 4, fill: ACCENT, stroke: '#141414', strokeWidth: 2 }}
              dot={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
      <div className="h-px hairline-x mt-3" />
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 pt-3">
        {CHANNEL_ORDER.map(channel => {
          const meta = CHANNEL_META[channel]
          return (
            <span key={channel} className="flex items-center gap-1.5 text-[11px] text-muted">
              <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: meta.color }} />
              {meta.label}
            </span>
          )
        })}
      </div>
    </GlassCard>
  )
}
