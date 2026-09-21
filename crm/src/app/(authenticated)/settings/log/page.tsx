'use client'

/**
 * /settings/log — linha do tempo de tudo que aconteceu no app, para compliance.
 *
 * Os eventos não vêm de uma tabela de auditoria: GET /api/audit-log junta as
 * tabelas que já registram cada coisa (mensagens, leads recebidos, movimentação
 * de card, disparos de funil). O motivo está documentado lá na rota.
 */

import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  ArrowClockwise, MagnifyingGlass, ArrowDown, ArrowUp, UserPlus,
  ArrowsLeftRight, Lightning, DownloadSimple,
} from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { formatPhone } from '@/lib/utils'

interface Evento {
  tipo: string
  quando: string
  lead_nome: string | null
  lead_telefone: string | null
  lead_id: string | null
  detalhe: string | null
  origem: string | null
  status: string | null
}

/** Rótulo, ícone e cor de cada tipo de evento. */
const TIPOS: Record<string, { label: string; icon: typeof ArrowDown; cor: string }> = {
  mensagem_recebida: { label: 'Mensagem recebida', icon: ArrowDown, cor: '#5fd39b' },
  mensagem_enviada: { label: 'Mensagem enviada', icon: ArrowUp, cor: '#7aa2f7' },
  lead_recebido: { label: 'Lead recebido', icon: UserPlus, cor: '#f2c744' },
  lead_movido: { label: 'Lead movido', icon: ArrowsLeftRight, cor: '#14b8a6' },
  funil_iniciado: { label: 'Funil iniciado', icon: Lightning, cor: '#8b5cf6' },
}

const PERIODOS = [
  { dias: 7, label: '7 dias' },
  { dias: 30, label: '30 dias' },
  { dias: 90, label: '90 dias' },
  { dias: 365, label: '1 ano' },
]

export default function LogPage() {
  const [eventos, setEventos] = useState<Evento[]>([])
  const [resumo, setResumo] = useState<Record<string, number>>({})
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [tipo, setTipo] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [dias, setDias] = useState(30)

  const carregar = useCallback(async () => {
    setCarregando(true)
    setErro(null)
    try {
      const params = new URLSearchParams({ dias: String(dias), limit: '300' })
      if (tipo) params.set('tipo', tipo)
      if (busca.trim()) params.set('q', busca.trim())
      const res = await fetch(`/api/audit-log?${params}`)
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Falha ao carregar o log.')
      setEventos(json.data || [])
      setResumo(json.resumo || {})
    } catch (e: any) {
      setErro(e.message || 'Falha ao carregar o log.')
      setEventos([])
    } finally {
      setCarregando(false)
    }
  }, [tipo, busca, dias])

  // Busca com atraso: digitar não dispara uma requisição por tecla.
  useEffect(() => {
    const t = setTimeout(carregar, busca ? 300 : 0)
    return () => clearTimeout(t)
  }, [carregar, busca])

  const total = useMemo(
    () => Object.values(resumo).reduce((a, b) => a + b, 0),
    [resumo]
  )

  /** Exporta o que está na tela — compliance costuma pedir o arquivo. */
  const exportarCsv = () => {
    const cab = ['Data', 'Evento', 'Lead', 'Telefone', 'Detalhe', 'Origem', 'Status']
    const escapar = (v: unknown) => `"${String(v ?? '').replace(/"/g, '""')}"`
    const linhas = eventos.map((e) => [
      new Date(e.quando).toLocaleString('pt-BR'),
      TIPOS[e.tipo]?.label ?? e.tipo,
      e.lead_nome ?? '',
      e.lead_telefone ?? '',
      e.detalhe ?? '',
      e.origem ?? '',
      e.status ?? '',
    ].map(escapar).join(';'))

    // BOM na frente: sem ele o Excel abre os acentos errados.
    const blob = new Blob(['﻿' + [cab.join(';'), ...linhas].join('\n')], {
      type: 'text/csv;charset=utf-8',
    })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `log-titacrm-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink">Log de eventos</h1>
          <p className="text-sm text-muted mt-1">
            Tudo que o sistema registrou: mensagens recebidas e enviadas, leads
            chegando, cards mudando de coluna e funis disparados.
          </p>
        </div>
        <button
          onClick={exportarCsv}
          disabled={eventos.length === 0}
          className="btn btn-outline btn-sm"
        >
          <DownloadSimple size={15} weight="bold" />
          Exportar CSV
        </button>
      </div>

      {/* Período */}
      <div className="flex flex-wrap items-center gap-2">
        {PERIODOS.map((p) => (
          <button
            key={p.dias}
            onClick={() => setDias(p.dias)}
            className={`pill ${dias === p.dias ? 'pill-active' : ''}`}
          >
            {p.label}
          </button>
        ))}
      </div>

      {/* Tipos de evento, com a contagem do período */}
      <div className="flex flex-wrap items-center gap-2">
        <button
          onClick={() => setTipo(null)}
          className={`pill ${tipo === null ? 'pill-active' : ''}`}
        >
          Todos
          <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">{total}</span>
        </button>
        {Object.entries(TIPOS).map(([chave, meta]) => {
          const Icon = meta.icon
          const qtd = resumo[chave] ?? 0
          return (
            <button
              key={chave}
              onClick={() => setTipo(tipo === chave ? null : chave)}
              className={`pill ${tipo === chave ? 'pill-active' : ''}`}
            >
              <Icon size={13} weight="bold" style={{ color: meta.cor }} />
              {meta.label}
              <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">{qtd}</span>
            </button>
          )
        })}
      </div>

      <div className="flex items-center gap-2">
        <div className="relative flex-1 max-w-sm">
          <MagnifyingGlass
            size={15}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted pointer-events-none"
          />
          <input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Buscar por nome ou telefone…"
            className="field !pl-9 !py-2 !text-xs"
          />
        </div>
        <button onClick={carregar} className="btn-icon w-9 h-9" title="Atualizar">
          <ArrowClockwise size={16} weight="bold" />
        </button>
      </div>

      {erro && (
        <div className="glass rounded-xl border-red-500/30 px-4 py-3">
          <p className="text-sm text-red-300">{erro}</p>
        </div>
      )}

      {carregando ? (
        <div className="flex items-center justify-center py-20">
          <LoadingSpinner text="Carregando eventos…" />
        </div>
      ) : eventos.length === 0 ? (
        <div className="glass rounded-2xl px-6 py-16 text-center">
          <p className="text-sm font-semibold text-ink">Nenhum evento no período.</p>
          <p className="text-xs text-muted mt-1.5">
            Mensagens, leads e movimentações aparecem aqui assim que acontecerem.
          </p>
        </div>
      ) : (
        <>
          <div className="glass-sunken rounded-2xl overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-xs">
                <thead>
                  <tr>
                    {['Quando', 'Evento', 'Lead', 'Detalhe', 'Origem'].map((h, i) => (
                      <th
                        key={h}
                        style={{ minWidth: [150, 170, 200, 320, 120][i] }}
                        className="sticky top-0 z-10 text-left font-semibold text-muted uppercase tracking-wider text-[10px] px-3.5 py-2.5 whitespace-nowrap surface-raised"
                      >
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {eventos.map((e, i) => {
                    const meta = TIPOS[e.tipo]
                    const Icon = meta?.icon ?? ArrowDown
                    return (
                      <tr key={i} className="border-t border-white/[0.06] hover:bg-white/[0.03] transition-colors">
                        <td className="px-3.5 py-2.5 text-muted tabular-nums whitespace-nowrap align-top">
                          {new Date(e.quando).toLocaleString('pt-BR')}
                        </td>
                        <td className="px-3.5 py-2.5 whitespace-nowrap align-top">
                          <span className="inline-flex items-center gap-1.5 text-ink">
                            <Icon size={13} weight="bold" style={{ color: meta?.cor ?? 'var(--muted)' }} />
                            {meta?.label ?? e.tipo}
                          </span>
                        </td>
                        <td className="px-3.5 py-2.5 align-top">
                          <span className="text-ink">{e.lead_nome || '—'}</span>
                          {e.lead_telefone && (
                            <span className="block text-[10px] text-muted tabular-nums">
                              {formatPhone(e.lead_telefone)}
                            </span>
                          )}
                        </td>
                        <td className="px-3.5 py-2.5 align-top text-muted max-w-[320px]">
                          <span className="line-clamp-2">{e.detalhe || '—'}</span>
                        </td>
                        <td className="px-3.5 py-2.5 align-top whitespace-nowrap">
                          <span className="text-muted">{e.origem || '—'}</span>
                          {e.status && (
                            <span className="block text-[10px] text-muted/70">{e.status}</span>
                          )}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </div>
          <p className="text-[11px] text-muted text-center">
            {eventos.length} evento(s) — dos {total} registrados nos últimos {dias} dias
          </p>
        </>
      )}
    </div>
  )
}
