'use client'

/**
 * ESTEIRA DE FOLLOW-UP (Pedro, 02/11/2026): "uma esteira de follow-up por dia contendo todos que vão receber follow-up nos
 * próximos dias, de todas as Nays e de todos os lugares ... se eu pôr no card uma lembrança de follow-up ele vai aparecer na
 * lista, e os follow-ups manuais e automáticos". Uma coluna por dia (hoje e os próximos); cada cartão diz quem recebe, por qual
 * Nay, se é manual (marcado no card) ou automático (a regra da Nay) e o que será mandado. Lê /api/esteira-followups.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { ArrowsClockwise, CircleNotch, Robot, UserCircle, Queue } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'

interface Item {
  dia: string | null; quando: string | null; janela?: string; nay: string; tipo: 'manual' | 'automatico'; origem: string
  titulo: string; nome: string | null; telefone: string | null; estado: string; detalhe?: string; leadId?: string; criadoPor?: string
}
interface Resposta { hoje: string; dias: number; itens: Item[]; semData: Item[] }

const NAYS = ['Todas', 'Parceria', 'Leads', 'Oficial', 'Captação'] as const
const ESTADO: Record<string, { r: string; cor: string }> = {
  previsto: { r: 'previsto', cor: 'var(--blue)' }, enviado: { r: 'enviado', cor: '#16a34a' }, pulado: { r: 'pulado', cor: '#d97706' },
  desligado: { r: 'automático desligado', cor: '#dc2626' }, falhou: { r: 'falhou', cor: '#dc2626' }, erro: { r: 'erro', cor: '#dc2626' },
  fila: { r: 'na fila', cor: 'var(--muted)' },
}

function nomeDoDia(iso: string, hoje: string): string {
  const d = new Date(iso + 'T12:00:00-04:00')
  const dif = Math.round((d.getTime() - new Date(hoje + 'T12:00:00-04:00').getTime()) / 86400000)
  const sem = d.toLocaleDateString('pt-BR', { weekday: 'long', timeZone: 'America/Manaus' })
  const data = d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' })
  return `${dif === 0 ? 'Hoje' : dif === 1 ? 'Amanhã' : sem[0].toUpperCase() + sem.slice(1)} · ${data}`
}
function hora(iso: string | null): string {
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' }) : ''
}

function Cartao({ i }: { i: Item }) {
  const e = ESTADO[i.estado] || { r: i.estado, cor: 'var(--muted)' }
  const corpo = (
    <div className="rounded-lg border border-line bg-panel p-2.5 flex flex-col gap-1 hover:border-accent/60 transition">
      <div className="flex items-center justify-between gap-2 text-[11px]">
        <span className="inline-flex items-center gap-1 text-muted">
          {i.tipo === 'manual' ? <UserCircle size={13} weight="fill" /> : <Robot size={13} weight="fill" />}
          {i.nay} · {i.tipo === 'manual' ? 'manual' : 'automático'}
        </span>
        <span className="font-semibold" style={{ color: e.cor }}>{e.r}</span>
      </div>
      <div className="text-[13px] font-semibold text-ink leading-4 truncate">{i.nome || i.telefone || '—'}</div>
      <div className="text-[12px] text-ink leading-4">{i.titulo}</div>
      {i.detalhe && <div className="text-[11.5px] text-muted leading-4 line-clamp-3">{i.detalhe}</div>}
      <div className="text-[11px] text-muted flex items-center justify-between">
        <span>{i.janela ? i.janela : hora(i.quando)}</span>
        {i.criadoPor && <span>por {i.criadoPor}</span>}
      </div>
    </div>
  )
  return i.leadId ? <Link href={linkDaConversa(i.leadId)} title="Abrir a conversa">{corpo}</Link> : corpo
}

export default function EsteiraDeFollowups() {
  const [dados, setDados] = useState<Resposta | null>(null)
  const [carregando, setCarregando] = useState(false)
  const [erro, setErro] = useState('')
  const [nay, setNay] = useState<(typeof NAYS)[number]>('Todas')
  const [tipo, setTipo] = useState<'todos' | 'manual' | 'automatico'>('todos')
  const [dias, setDias] = useState(7)

  const ler = useCallback(async () => {
    setCarregando(true)
    setErro('')
    try {
      const r = await fetch(`/api/esteira-followups?dias=${dias}`)
      const j = await r.json()
      if (!r.ok) throw new Error(j.error || 'Não consegui ler a esteira.')
      setDados(j)
    } catch (e: any) { setErro(e?.message || 'Não consegui ler a esteira.') } finally { setCarregando(false) }
  }, [dias])
  useEffect(() => { void ler() }, [ler])

  const passa = useCallback((i: Item) => (nay === 'Todas' || i.nay === nay || i.nay === 'Todas') && (tipo === 'todos' || i.tipo === tipo), [nay, tipo])
  const colunas = useMemo(() => {
    if (!dados) return []
    const lista: string[] = []
    for (let k = 0; k < dados.dias; k++) lista.push(new Date(new Date(dados.hoje + 'T12:00:00-04:00').getTime() + k * 86400000).toISOString().slice(0, 10))
    return lista.map((d) => ({ dia: d, itens: dados.itens.filter((i) => i.dia === d && passa(i)) }))
  }, [dados, passa])
  const semData = (dados?.semData || []).filter(passa)
  const total = colunas.reduce((s, c) => s + c.itens.filter((i) => i.estado !== 'enviado' && i.estado !== 'pulado').length, 0)

  return (
    <div className="p-4 md:p-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-ink flex items-center gap-2"><Queue size={24} weight="fill" className="text-accent" /> Esteira de follow-up</h1>
          <p className="text-sm text-muted mt-1">Quem vai receber follow-up, dia a dia, de todas as Nays: os que você marca no card e os automáticos de cada Nay.
            {dados && <> <b className="text-ink">{total}</b> pela frente nos próximos {dados.dias} dias.</>}</p>
        </div>
        <button type="button" onClick={() => void ler()} className="h-9 px-3 rounded-lg border border-line text-sm text-ink flex items-center gap-1.5" title="Ler de novo">
          {carregando ? <CircleNotch size={15} className="animate-spin" /> : <ArrowsClockwise size={15} />} Atualizar
        </button>
      </div>

      <div className="mt-4 flex items-center gap-2 flex-wrap text-sm">
        {NAYS.map((n) => (
          <button key={n} type="button" onClick={() => setNay(n)}
                  className={`px-3 h-8 rounded-full border ${nay === n ? 'bg-accent/15 border-accent/40 text-accent font-semibold' : 'border-line text-ink'}`}>{n}</button>
        ))}
        <span className="mx-1 text-muted">|</span>
        {([['todos', 'Manuais e automáticos'], ['manual', 'Só manuais'], ['automatico', 'Só automáticos']] as const).map(([k, r]) => (
          <button key={k} type="button" onClick={() => setTipo(k)}
                  className={`px-3 h-8 rounded-full border ${tipo === k ? 'bg-accent/15 border-accent/40 text-accent font-semibold' : 'border-line text-ink'}`}>{r}</button>
        ))}
        <select value={dias} onChange={(e) => setDias(Number(e.target.value))} className="h-8 rounded-md border border-line bg-panel text-ink px-2" aria-label="Quantos dias">
          {[3, 7, 14, 30].map((n) => <option key={n} value={n}>próximos {n} dias</option>)}
        </select>
      </div>

      {erro && <p className="mt-4 text-sm" style={{ color: '#dc2626' }}>{erro}</p>}
      {!dados && !erro && <p className="mt-6 text-sm text-muted">Lendo a esteira…</p>}

      {dados && (
        <div className="mt-4 flex gap-3 overflow-x-auto pb-3">
          {colunas.map((c) => (
            <section key={c.dia} className="w-[280px] shrink-0">
              <h2 className="text-[13px] font-bold text-ink mb-2 flex items-center justify-between">
                {nomeDoDia(c.dia, dados.hoje)}<span className="text-muted font-semibold">{c.itens.length}</span>
              </h2>
              <div className="flex flex-col gap-2">
                {c.itens.length ? c.itens.map((i, n) => <Cartao key={`${c.dia}-${n}`} i={i} />)
                  : <p className="text-[12px] text-muted rounded-lg border border-dashed border-line p-3">Nada marcado para este dia.</p>}
              </div>
            </section>
          ))}
          <section className="w-[280px] shrink-0">
            <h2 className="text-[13px] font-bold text-ink mb-2 flex items-center justify-between">Sem dia marcado<span className="text-muted font-semibold">{semData.length}</span></h2>
            <div className="flex flex-col gap-2">{semData.map((i, n) => <Cartao key={`sd-${n}`} i={i} />)}</div>
          </section>
        </div>
      )}
      <p className="text-[11.5px] text-muted mt-2">
        O follow-up marcado no card (manual) aparece aqui na hora e sai no horário pela linha da conversa. Os automáticos são previstos pelas
        regras de cada Nay: o &quot;seu cliente tem interesse?&quot; do dia seguinte da Parceria só vale para quem recebeu imóvel e não conversou nem recusou antes.
      </p>
    </div>
  )
}
