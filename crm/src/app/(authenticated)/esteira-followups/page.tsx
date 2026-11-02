'use client'

/**
 * ESTEIRA DE FOLLOW-UP (Pedro, 02/11/2026): "uma esteira de follow-up por dia contendo todos que vão receber follow-up nos
 * próximos dias, de todas as Nays e de todos os lugares ... se eu pôr no card uma lembrança de follow-up ele vai aparecer na
 * lista, e os follow-ups manuais e automáticos". Uma coluna por dia (hoje e os próximos); cada cartão diz quem recebe, por qual
 * Nay, se é manual (marcado no card) ou automático (a regra da Nay) e o que será mandado. Lê /api/esteira-followups.
 *
 * 02/11, mais tarde (Pedro: "ficou ruim de ver ... precisa de tags de qual número é e um quadrado Motivo explicando o porquê,
 * e tem muitos dias lá, deixa só 3 dias aparecendo e mais largos, com uma barrinha de rolar embaixo"): cada cartão tem a
 * etiqueta do número que manda e o quadro Motivo; cabem 3 dias na tela, e os outros vêm pela barra de baixo (ou pelas setas).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import Link from 'next/link'
import { ArrowsClockwise, CaretLeft, CaretRight, CircleNotch, Robot, UserCircle, Queue } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'

interface Item {
  dia: string | null; quando: string | null; janela?: string; nay: string; tipo: 'manual' | 'automatico'; origem: string
  titulo: string; nome: string | null; telefone: string | null; estado: string; detalhe?: string; leadId?: string; criadoPor?: string
  motivo?: string
}
interface Resposta { hoje: string; dias: number; itens: Item[]; semData: Item[] }

const NAYS = ['Todas', 'Parceria', 'Leads', 'Oficial', 'Captação'] as const
const ESTADO: Record<string, { r: string; cor: string }> = {
  previsto: { r: 'previsto', cor: 'var(--blue)' }, enviado: { r: 'enviado', cor: '#16a34a' }, pulado: { r: 'pulado', cor: '#d97706' },
  desligado: { r: 'automático desligado', cor: '#dc2626' }, falhou: { r: 'falhou', cor: '#dc2626' }, erro: { r: 'erro', cor: '#dc2626' },
  fila: { r: 'na fila', cor: 'var(--muted)' },
}
/* o número que manda cada follow-up (a retomada da captação sai pelo oficial) */
const NUMERO: Record<string, { r: string; cor: string }> = {
  Parceria: { r: 'Parceria · 9445-3618', cor: '#7c3aed' },
  Leads: { r: 'Leads · 8595-6408', cor: '#0891b2' },
  Oficial: { r: 'Oficial · 8456-0874', cor: '#16a34a' },
  'Captação': { r: 'Oficial · 8456-0874 (captação)', cor: '#16a34a' },
  Todas: { r: 'Todos os números', cor: '#64748b' },
  CRM: { r: 'Número da conversa', cor: '#64748b' },
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
  const n = NUMERO[i.nay] || NUMERO.CRM
  const corpo = (
    <div className="rounded-lg border border-line bg-panel p-3 flex flex-col gap-1.5 hover:border-accent/60 transition">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <span className="px-2 py-0.5 rounded-full text-[11px] font-bold"
              style={{ color: n.cor, background: `color-mix(in srgb, ${n.cor} 14%, transparent)`, border: `1px solid color-mix(in srgb, ${n.cor} 35%, transparent)` }}>
          {n.r}
        </span>
        <span className="text-[11px] font-semibold" style={{ color: e.cor }}>{e.r}</span>
      </div>
      <div className="flex items-center justify-between gap-2">
        <span className="text-[14px] font-semibold text-ink leading-5 truncate">{i.nome || i.telefone || '—'}</span>
        <span className="text-[12px] text-muted shrink-0">{i.janela ? i.janela : hora(i.quando)}</span>
      </div>
      <div className="text-[12.5px] text-ink leading-4 flex items-center gap-1">
        <span className="text-muted inline-flex items-center gap-1 shrink-0">
          {i.tipo === 'manual' ? <UserCircle size={13} weight="fill" /> : <Robot size={13} weight="fill" />}
          {i.tipo === 'manual' ? 'Manual' : 'Automático'} ·
        </span>
        <span>{i.titulo}</span>
      </div>
      {i.motivo && (
        <div className="rounded-md border border-line px-2.5 py-1.5" style={{ background: 'color-mix(in srgb, var(--blue, #3b82f6) 7%, transparent)' }}>
          <div className="text-[10.5px] font-bold uppercase tracking-wide text-muted">Motivo</div>
          <div className="text-[12px] text-ink leading-4">{i.motivo}</div>
        </div>
      )}
      {i.detalhe && i.estado !== 'pulado' && (
        <div className="text-[11.5px] text-muted leading-4 line-clamp-3">{i.tipo === 'manual' ? 'Mensagem: ' : ''}{i.detalhe}</div>
      )}
      {i.criadoPor && <div className="text-[11px] text-muted text-right">por {i.criadoPor}</div>}
    </div>
  )
  return i.leadId ? <Link href={linkDaConversa(i.leadId)} title="Abrir a conversa">{corpo}</Link> : corpo
}

function Coluna({ titulo, itens, vazio }: { titulo: string; itens: Item[]; vazio: string }) {
  return (
    <section className="esteira-coluna shrink-0 snap-start flex flex-col rounded-xl border border-line p-2.5"
             style={{ background: 'color-mix(in srgb, var(--panel, #fff) 60%, transparent)' }}>
      <h2 className="text-[14px] font-bold text-ink mb-2 px-0.5 flex items-center justify-between">
        {titulo}<span className="text-muted font-semibold text-[12.5px]">{itens.length}</span>
      </h2>
      <div className="esteira-rolagem flex flex-col gap-2 overflow-y-auto pr-1" style={{ maxHeight: 'calc(100vh - 300px)' }}>
        {itens.length ? itens.map((i, n) => <Cartao key={n} i={i} />)
          : <p className="text-[12px] text-muted rounded-lg border border-dashed border-line p-3">{vazio}</p>}
      </div>
    </section>
  )
}

export default function EsteiraDeFollowups() {
  const [dados, setDados] = useState<Resposta | null>(null)
  const [carregando, setCarregando] = useState(false)
  const [erro, setErro] = useState('')
  const [nay, setNay] = useState<(typeof NAYS)[number]>('Todas')
  const [tipo, setTipo] = useState<'todos' | 'manual' | 'automatico'>('todos')
  const [dias, setDias] = useState(7)
  const trilho = useRef<HTMLDivElement>(null)

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
  // as setas andam um dia (uma coluna) para cada lado
  const andar = (lado: 1 | -1) => {
    const t = trilho.current
    const col = t?.querySelector<HTMLElement>('.esteira-coluna')
    if (t && col) t.scrollBy({ left: lado * (col.offsetWidth + 12), behavior: 'smooth' })
  }

  return (
    <div className="p-4 md:p-6">
      <div className="flex items-start justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-ink flex items-center gap-2"><Queue size={24} weight="fill" className="text-accent" /> Esteira de follow-up</h1>
          <p className="text-sm text-muted mt-1">Quem vai receber follow-up, dia a dia, de todas as Nays: os que você marca no card e os automáticos de cada Nay.
            {dados && <> <b className="text-ink">{total}</b> pela frente nos próximos {dados.dias} dias.</>}</p>
        </div>
        <div className="flex items-center gap-2">
          <button type="button" onClick={() => andar(-1)} className="h-9 w-9 rounded-lg border border-line text-ink flex items-center justify-center" title="Dia anterior" aria-label="Dia anterior"><CaretLeft size={16} /></button>
          <button type="button" onClick={() => andar(1)} className="h-9 w-9 rounded-lg border border-line text-ink flex items-center justify-center" title="Próximo dia" aria-label="Próximo dia"><CaretRight size={16} /></button>
          <button type="button" onClick={() => void ler()} className="h-9 px-3 rounded-lg border border-line text-sm text-ink flex items-center gap-1.5" title="Ler de novo">
            {carregando ? <CircleNotch size={15} className="animate-spin" /> : <ArrowsClockwise size={15} />} Atualizar
          </button>
        </div>
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
        <div ref={trilho} className="esteira-rolagem esteira-trilho mt-4 flex gap-3 overflow-x-auto pb-3 snap-x snap-mandatory">
          {colunas.map((c) => <Coluna key={c.dia} titulo={nomeDoDia(c.dia, dados.hoje)} itens={c.itens} vazio="Nada marcado para este dia." />)}
          <Coluna titulo="Sem dia marcado" itens={semData} vazio="Nada na fila." />
        </div>
      )}
      <p className="text-[11.5px] text-muted mt-2">
        Aparecem 3 dias por vez: para ver os outros, use a barra de rolagem embaixo ou as setas lá em cima. O follow-up marcado no card
        (manual) aparece aqui na hora e sai no horário pela linha da conversa. Os automáticos são previstos pelas regras de cada Nay.
      </p>
    </div>
  )
}
