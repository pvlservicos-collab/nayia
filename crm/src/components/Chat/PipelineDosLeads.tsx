'use client'

/**
 * O PIPELINE DOS LEADS (Pedro, 24/10/2026: "quero que todos os leads que cheguem na aba leads fiquem em um pipeline lá
 * do lado de visitas com a data que chegaram e até onde foram, se pararam na busca, se visitaram").
 *
 * Uma coluna por ponto do caminho; cada lead fica na coluna MAIS LONGE a que chegou (migração 491,
 * crm_leads_pipeline), não na etapa de agora: quem visitou e depois foi finalizado continua em "Visitou".
 * O filtro é pela data em que o lead chegou (dia de Manaus); cada coluna rola sozinha. Clicar abre a conversa.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowClockwise, CircleNotch, User } from '@phosphor-icons/react'
import { FUSO_DE_MANAUS, diaEmManaus } from '@/lib/fusoDeManaus'
import { fim8 } from '@/lib/olxClientes'

interface LeadDoPipeline {
  id: number
  telefone: string
  nome: string | null
  origem: string
  codigo: number | null
  chegou_em: string
  ultimo_em: string
  etapa: string
  foi_ate: string
  imoveis: number
  humano: boolean
  parada_motivo: string | null
  visita_quando: string | null
  procura: string | null
}

const COLUNAS: { chave: string; rotulo: string; cor: string }[] = [
  { chave: 'chegou', rotulo: 'Chegou', cor: '#94a3b8' },
  { chave: 'busca', rotulo: 'Parou na busca', cor: '#f59e0b' },
  { chave: 'enviados', rotulo: 'Recebeu imóveis', cor: '#0ea5e9' },
  { chave: 'visita', rotulo: 'Pediu visita', cor: '#8b5cf6' },
  { chave: 'confirmada', rotulo: 'Visita confirmada', cor: '#6366f1' },
  { chave: 'visitou', rotulo: 'Visitou', cor: '#22c55e' },
  { chave: 'fechou', rotulo: 'Fechou', cor: '#15803d' },
  { chave: 'proprietario', rotulo: 'Era proprietário', cor: '#b45309' },
]

const ORIGEM: Record<string, string> = { olx: 'OLX', organico: 'Orgânico', manual: 'Pelo CRM' }
const ETAPA_DE_AGORA: Record<string, string> = {
  nova: 'nova', filtrar: 'filtrando', feito_busca: 'busca feita', imoveis_enviados: 'imóveis enviados', visita: 'visita',
  proprietarios: 'proprietário', fechamento: 'fechamento', finalizado: 'finalizado',
}

const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', {
  timeZone: FUSO_DE_MANAUS, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
})
const telefoneBonito = (t: string) => {
  const d = String(t || '').replace(/\D/g, '').replace(/^55/, '')
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : t
}

export default function PipelineDosLeads({ leadsDoCrm, aoAbrirConversa }: {
  leadsDoCrm: { id: string; phone?: string | null }[]
  aoAbrirConversa: (leadId: string) => void
}) {
  const [ate, setAte] = useState(() => diaEmManaus())
  const [de, setDe] = useState(() => diaEmManaus(new Date(Date.now() - 30 * 86400_000)))
  const [leads, setLeads] = useState<LeadDoPipeline[]>([])
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState('')

  const carregar = useCallback(async () => {
    setCarregando(true)
    try {
      const r = await fetch(`/api/captacao/pipeline-leads?de=${de}&ate=${ate}`)
      const j = await r.json()
      if (!r.ok) throw new Error(j?.error || 'falhou')
      setLeads(j.leads || [])
      setErro('')
    } catch (e: any) {
      setErro(e?.message || 'Não consegui ler o pipeline.')
    }
    setCarregando(false)
  }, [de, ate])
  useEffect(() => { carregar() }, [carregar])
  useEffect(() => { const t = setInterval(carregar, 60_000); return () => clearInterval(t) }, [carregar])

  // o lead do CRM pelo telefone (8 últimos dígitos), para abrir a conversa
  const doCrm = useMemo(() => {
    const m = new Map<string, string>()
    for (const l of leadsDoCrm) { const k = fim8(l.phone); if (k.length === 8 && !m.has(k)) m.set(k, l.id) }
    return m
  }, [leadsDoCrm])

  const porColuna = useMemo(() => {
    const m: Record<string, LeadDoPipeline[]> = {}
    for (const l of leads) (m[l.foi_ate] ||= []).push(l)
    return m
  }, [leads])

  return (
    <div className="flex-1 min-h-0 flex flex-col" style={{ background: 'var(--wa-app)' }}>
      <div className="flex flex-wrap items-center gap-2 px-4 py-2.5" style={{ borderBottom: '1px solid var(--wa-divider)', background: 'var(--wa-panel)' }}>
        <b className="text-[14px]" style={{ color: 'var(--wa-text)' }}>Leads que chegaram</b>
        <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>de</span>
        <input type="date" value={de} max={ate} onChange={(e) => e.target.value && setDe(e.target.value)}
               className="text-[13px] rounded-md px-2 py-1" style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-input)', color: 'var(--wa-text)' }} />
        <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>até</span>
        <input type="date" value={ate} min={de} onChange={(e) => e.target.value && setAte(e.target.value)}
               className="text-[13px] rounded-md px-2 py-1" style={{ border: '1px solid var(--wa-divider)', background: 'var(--wa-input)', color: 'var(--wa-text)' }} />
        <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>{leads.length} lead{leads.length === 1 ? '' : 's'}</span>
        <button type="button" onClick={carregar} title="Atualizar" className="ml-auto p-1.5 rounded-full hover:bg-black/5" style={{ color: 'var(--wa-icon)' }}>
          {carregando ? <CircleNotch size={18} className="animate-spin" /> : <ArrowClockwise size={18} />}
        </button>
      </div>
      {erro && <div className="px-4 py-2 text-[13px] text-red-600">{erro}</div>}
      <div className="flex-1 min-h-0 flex gap-3 overflow-x-auto p-3">
        {COLUNAS.map((c) => {
          const lista = porColuna[c.chave] || []
          return (
            <div key={c.chave} className="flex-shrink-0 w-[250px] flex flex-col min-h-0 rounded-lg" style={{ background: 'var(--wa-panel)', boxShadow: 'var(--wa-shadow)' }}>
              <div className="flex items-center gap-2 px-3 py-2" style={{ borderBottom: `3px solid ${c.cor}` }}>
                <span className="text-[13px] font-semibold" style={{ color: 'var(--wa-text)' }}>{c.rotulo}</span>
                <span className="ml-auto text-[12px] font-semibold rounded-full px-2" style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-chip-ink)' }}>{lista.length}</span>
              </div>
              <div className="flex-1 min-h-0 overflow-y-auto p-2 flex flex-col gap-2">
                {lista.map((l) => {
                  const idCrm = doCrm.get(fim8(l.telefone))
                  return (
                    <button key={l.id} type="button" disabled={!idCrm} onClick={() => idCrm && aoAbrirConversa(idCrm)}
                            title={idCrm ? 'Abrir a conversa' : 'A conversa ainda não está no CRM'}
                            className="text-left rounded-md px-2.5 py-2 hover:brightness-95 disabled:cursor-default"
                            style={{ background: 'var(--wa-app)', borderLeft: `3px solid ${c.cor}` }}>
                      <div className="flex items-center gap-1.5">
                        <User size={13} style={{ color: 'var(--wa-icon)' }} />
                        <span className="text-[13px] font-semibold truncate" style={{ color: 'var(--wa-text)' }}>{l.nome || telefoneBonito(l.telefone)}</span>
                      </div>
                      {l.nome && <div className="text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>{telefoneBonito(l.telefone)}</div>}
                      <div className="text-[11.5px] mt-0.5" style={{ color: 'var(--wa-text-2)' }}>
                        Chegou {dataHora(l.chegou_em)} · {ORIGEM[l.origem] || l.origem}{l.codigo ? ` · #${l.codigo}` : ''}
                      </div>
                      {l.procura && <div className="text-[11.5px] mt-0.5 line-clamp-2" style={{ color: 'var(--wa-text)' }}>{l.procura}</div>}
                      <div className="flex flex-wrap gap-1 mt-1">
                        {l.imoveis > 0 && <span className="text-[10.5px] rounded px-1.5" style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-chip-ink)' }}>{l.imoveis} imóve{l.imoveis === 1 ? 'l' : 'is'}</span>}
                        {l.visita_quando && <span className="text-[10.5px] rounded px-1.5" style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-chip-ink)' }}>visita {dataHora(l.visita_quando)}</span>}
                        <span className="text-[10.5px] rounded px-1.5" style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-chip-ink)' }}>agora: {ETAPA_DE_AGORA[l.etapa] || l.etapa}</span>
                        {l.humano && <span className="text-[10.5px] rounded px-1.5" style={{ background: '#fce7f3', color: '#be185d' }}>com a equipe</span>}
                      </div>
                      <div className="text-[10.5px] mt-1" style={{ color: 'var(--wa-text-2)' }}>Último movimento {dataHora(l.ultimo_em)}</div>
                    </button>
                  )
                })}
                {!lista.length && !carregando && <p className="text-[12px] text-center py-4" style={{ color: 'var(--wa-text-2)' }}>Ninguém</p>}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
