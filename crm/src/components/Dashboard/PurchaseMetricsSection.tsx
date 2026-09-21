import { ShoppingCart, Package, CurrencyCircleDollar } from '@phosphor-icons/react'
import GlassCard, { SectionHeader } from './GlassCard'
import { type PurchaseMetrics } from './mockData'

function formatCurrency(value: number) {
  return value.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

interface PurchaseMetricsSectionProps {
  metrics: PurchaseMetrics
}

export default function PurchaseMetricsSection({ metrics }: PurchaseMetricsSectionProps) {
  const items = [
    { key: 'sales', label: 'Vendas realizadas', value: metrics.salesCount.toLocaleString('pt-BR'), icon: ShoppingCart },
    { key: 'products', label: 'Produtos comprados', value: metrics.productsSold.toLocaleString('pt-BR'), icon: Package },
    { key: 'total', label: 'TOTAL', value: formatCurrency(metrics.totalValue), icon: CurrencyCircleDollar, highlight: true },
  ]

  return (
    <section>
      <SectionHeader icon={<ShoppingCart size={16} weight="bold" />} title="Métricas de compra" />
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
        {items.map(item => {
          const Icon = item.icon
          return (
            <GlassCard key={item.key} className={`p-4 ${item.highlight ? 'border-accent/30 bg-accent/[0.06]' : ''}`}>
              <div className="flex items-center gap-2 mb-3">
                <Icon size={16} className={item.highlight ? 'text-accent-2' : 'text-muted'} weight="bold" />
                <p className="text-xs font-medium text-muted">{item.label}</p>
              </div>
              <p className={`text-2xl font-bold leading-none ${item.highlight ? 'text-accent-2' : 'text-ink'}`}>{item.value}</p>
            </GlassCard>
          )
        })}
      </div>
    </section>
  )
}
