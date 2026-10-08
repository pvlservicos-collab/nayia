'use client'

import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks'
import { EMPTY_METRICS, type DashboardMetrics, type TopFollowUpMessage } from '@/components/Dashboard/mockData'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import RelatorioDiario from '@/components/Dashboard/RelatorioDiario'
import BusinessFlowDiagram from '@/components/Dashboard/BusinessFlowDiagram'
import ChannelStatsSection from '@/components/Dashboard/ChannelStatsSection'
import LeadsByDayChart from '@/components/Dashboard/LeadsByDayChart'
import PurchaseMetricsSection from '@/components/Dashboard/PurchaseMetricsSection'
import FollowUpMetricsSection from '@/components/Dashboard/FollowUpMetricsSection'

export default function InicioPage() {
    const { profileName, user, loading } = useAuth()

    const firstName = (profileName || user?.email || '').split(' ')[0] || ''

    // Números reais, contados no banco. Começa zerado e não com valor de
    // exemplo: um dashboard que mostra número plausível e falso engana sem
    // ninguém perceber, o que é pior que um zero honesto enquanto carrega.
    const [metrics, setMetrics] = useState<DashboardMetrics>(EMPTY_METRICS)
    const [metricsLoading, setMetricsLoading] = useState(true)

    useEffect(() => {
        let cancelado = false
        fetch('/api/metrics/dashboard?dias=30')
            .then((res) => (res.ok ? res.json() : null))
            .then((json) => { if (!cancelado && json?.data) setMetrics(json.data) })
            .catch(() => { /* fica no zerado — a tela continua legível */ })
            .finally(() => { if (!cancelado) setMetricsLoading(false) })
        return () => { cancelado = true }
    }, [])

    // O funil ainda não guarda o texto de cada mensagem separadamente, então o
    // "melhores mensagens" mostra por funil — que é o dado que existe hoje.
    const topMessages: TopFollowUpMessage[] = metrics.top_funis.map((f, i) => ({
        id: String(i),
        preview: f.name,
        responseRate: metrics.follow_up.followUpsSentCount > 0
            ? Math.round((metrics.follow_up.followUpRepliesCount / metrics.follow_up.followUpsSentCount) * 100)
            : 0,
        sentCount: f.sentCount,
    }))

    if (loading) {
        return (
            <div className="flex items-center justify-center h-[calc(100vh-56px)]">
                <LoadingSpinner text="Carregando..." size="lg" />
            </div>
        )
    }

    // ambient-glow desenha (via ::before/::after) os dois borrões que ficam atrás
    // dos cards translúcidos — ver globals.css. Antes eram duas divs decorativas
    // soltas aqui no meio do conteúdo.
    return (
        <div className="ambient-glow min-h-full">
            <div className="relative z-10 max-w-6xl mx-auto p-4 sm:p-6 space-y-8">
                <div className="pb-2">
                    <h1 className="text-2xl sm:text-3xl font-bold text-ink">
                        {firstName ? `Olá, ${firstName}` : 'Olá'}
                    </h1>
                    <p className="text-sm text-muted mt-1">
                        Visão geral do seu funil de aquisição e vendas
                        {metricsLoading ? ' — carregando…' : ` — últimos ${metrics.periodo_dias} dias`}.
                    </p>
                </div>

                {/* Primeiro de tudo: é o que o time lê de manhã e cola no grupo. */}
                <RelatorioDiario />

                <BusinessFlowDiagram />
                <ChannelStatsSection totals={metrics.fontes} />
                <LeadsByDayChart data={metrics.serie_diaria} />
                <PurchaseMetricsSection metrics={metrics.compras} />
                <FollowUpMetricsSection metrics={metrics.follow_up} topMessages={topMessages} />
            </div>
        </div>
    )
}
