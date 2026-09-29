'use client'

/**
 * CONFIGURAÇÕES > CORRETORES (Pedro, 29/09/2026): "fica em um menu lá em
 * configurações de corretores, ele vê os que mais interagem, mais agendam e os
 * documentos salvos lá".
 *
 * Os corretores parceiros (quem a Nay reconhece como corretor na Parceria),
 * com o período escolhido: mensagens dele e nossas, visitas pedidas e
 * realizadas, a pasta de documentos. Ordena por qualquer coluna; o nome abre a
 * conversa. Os dados vêm de /api/corretores.
 */
import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import { MagnifyingGlass, CaretDown, CaretUp, FolderSimple, FileText, ChatCircleText, CircleNotch, Copy, Check } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'
import { ETAPA_DA_NAY } from '@/lib/tiposNay'
import { numeroParaCopiar } from '@/components/Chat/PainelContatoParceria'

type Corretor = {
  leadId: string
  nome: string
  nomeNoCadastro: string | null
  telefone: string | null
  creci: string | null
  avatar: string | null
  etapa: string | null
  mensagensDele: number
  mensagensNossas: number
  ultimaMensagem: string | null
  visitasPedidas: number
  visitasRealizadas: number
  visitasAbertas: number
  documentos: number
}
type Documento = { id: string; nome: string; url: string; tamanho: number | null; criadoEm: string }
type Coluna = 'nome' | 'mensagensDele' | 'visitasPedidas' | 'visitasRealizadas' | 'documentos' | 'ultimaMensagem'

const PERIODOS: Array<[number, string]> = [[7, '7 dias'], [30, '30 dias'], [90, '90 dias'], [365, '1 ano']]

function quando(iso: string | null) {
  if (!iso) return '—'
  const d = new Date(iso)
  const dias = Math.floor((Date.now() - d.getTime()) / 86400000)
  if (dias <= 0) return 'hoje'
  if (dias === 1) return 'ontem'
  if (dias < 30) return `há ${dias} dias`
  return d.toLocaleDateString('pt-BR', { timeZone: 'America/Manaus' })
}

function Pasta({ leadId }: { leadId: string }) {
  const [docs, setDocs] = useState<Documento[] | null>(null)
  useEffect(() => {
    let vivo = true
    fetch(`/api/leads/${leadId}/documentos`).then((r) => r.json()).then((j) => { if (vivo) setDocs(j.documentos || []) }).catch(() => { if (vivo) setDocs([]) })
    return () => { vivo = false }
  }, [leadId])
  if (!docs) return <p className="text-sm text-muted py-2 flex items-center gap-2"><CircleNotch size={14} className="animate-spin" /> Abrindo a pasta…</p>
  if (!docs.length) return <p className="text-sm text-muted py-2">Nenhum documento. Anexe pelo card do contato, na conversa.</p>
  return (
    <ul className="grid gap-1.5 py-2 sm:grid-cols-2">
      {docs.map((d) => (
        <li key={d.id}>
          <a href={d.url} target="_blank" rel="noopener noreferrer"
             className="flex items-center gap-2 rounded-lg border border-line bg-panel px-3 py-2 text-sm hover:border-accent/60">
            <FileText size={18} className="text-muted flex-shrink-0" />
            <span className="truncate flex-1 text-ink">{d.nome}</span>
            <span className="text-xs text-muted flex-shrink-0">{new Date(d.criadoEm).toLocaleDateString('pt-BR')}</span>
          </a>
        </li>
      ))}
    </ul>
  )
}

function CopiarNumero({ telefone }: { telefone: string | null }) {
  const numero = numeroParaCopiar(telefone)
  const [ok, setOk] = useState(false)
  if (!numero) return <span className="text-muted">—</span>
  return (
    <button type="button" className="inline-flex items-center gap-1 text-sm text-ink-2 hover:text-ink" title="Copiar o número (sem o 55)"
            onClick={async () => { try { await navigator.clipboard.writeText(numero); setOk(true); setTimeout(() => setOk(false), 1500) } catch {} }}>
      {numero} {ok ? <Check size={13} weight="bold" className="text-accent" /> : <Copy size={13} />}
    </button>
  )
}

export default function CorretoresPage() {
  const [dias, setDias] = useState(30)
  const [lista, setLista] = useState<Corretor[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [ordem, setOrdem] = useState<{ col: Coluna; desc: boolean }>({ col: 'mensagensDele', desc: true })
  const [aberto, setAberto] = useState<string | null>(null)

  useEffect(() => {
    let vivo = true
    setLista(null); setErro(null)
    fetch(`/api/corretores?dias=${dias}`)
      .then(async (r) => { const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`); return j })
      .then((j) => { if (vivo) setLista(j.corretores || []) })
      .catch((e) => { if (vivo) setErro(e?.message || 'Não consegui carregar') })
    return () => { vivo = false }
  }, [dias])

  const linhas = useMemo(() => {
    const q = busca.trim().toLowerCase()
    const f = (lista || []).filter((c) => !q || [c.nome, c.nomeNoCadastro, c.creci, c.telefone].some((x) => String(x ?? '').toLowerCase().includes(q)))
    const valor = (c: Corretor) => ordem.col === 'nome' ? c.nome.toLowerCase()
      : ordem.col === 'ultimaMensagem' ? (c.ultimaMensagem ? Date.parse(c.ultimaMensagem) : 0)
      : (c[ordem.col] as number)
    return f.sort((a, b) => {
      const va = valor(a), vb = valor(b)
      const cmp = va < vb ? -1 : va > vb ? 1 : 0
      return ordem.desc ? -cmp : cmp
    })
  }, [lista, busca, ordem])

  const totais = useMemo(() => (lista || []).reduce((s, c) => ({
    mensagens: s.mensagens + c.mensagensDele, visitas: s.visitas + c.visitasPedidas, realizadas: s.realizadas + c.visitasRealizadas, documentos: s.documentos + c.documentos,
  }), { mensagens: 0, visitas: 0, realizadas: 0, documentos: 0 }), [lista])

  const Cabecalho = ({ col, children, alinhar = 'right' }: { col: Coluna; children: React.ReactNode; alinhar?: 'left' | 'right' }) => (
    <th className={`px-3 py-2.5 font-semibold text-xs uppercase tracking-wide text-muted ${alinhar === 'right' ? 'text-right' : 'text-left'}`}>
      <button type="button" className="inline-flex items-center gap-1 hover:text-ink"
              onClick={() => setOrdem((o) => ({ col, desc: o.col === col ? !o.desc : col !== 'nome' }))}>
        {children}
        {ordem.col === col && (ordem.desc ? <CaretDown size={11} weight="bold" /> : <CaretUp size={11} weight="bold" />)}
      </button>
    </th>
  )

  return (
    <div className="max-w-6xl mx-auto space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink">Corretores</h1>
          <p className="text-sm text-muted mt-1">Os corretores parceiros que falam com a Nay: quem mais conversa, quem mais agenda visita e os documentos de cada um.</p>
        </div>
        <div className="flex items-center gap-1 rounded-lg border border-line bg-panel p-0.5">
          {PERIODOS.map(([d, r]) => (
            <button key={d} type="button" onClick={() => setDias(d)}
                    className={`px-3 py-1.5 rounded-md text-xs font-semibold ${dias === d ? 'bg-accent/15 text-accent' : 'text-ink-2 hover:text-ink'}`}>
              {r}
            </button>
          ))}
        </div>
      </div>

      {lista && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[['Corretores', lista.length], [`Mensagens deles (${dias}d)`, totais.mensagens], [`Visitas pedidas (${dias}d)`, totais.visitas], ['Documentos guardados', totais.documentos]]
            .map(([r, n]) => (
              <div key={String(r)} className="rounded-xl border border-line bg-panel px-4 py-3">
                <p className="text-xs text-muted">{r}</p>
                <p className="text-2xl font-bold text-ink tabular-nums">{n}</p>
              </div>
            ))}
        </div>
      )}

      <div className="relative">
        <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" size={18} />
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar por nome, CRECI ou número…"
               className="block w-full pl-10 pr-3 py-2.5 border border-line rounded-xl bg-panel text-sm placeholder-muted focus:outline-none focus:ring-2 focus:ring-accent" />
      </div>

      {erro ? (
        <p className="text-sm text-red-500">Não consegui carregar os corretores: {erro}</p>
      ) : !lista ? (
        <p className="text-sm text-muted flex items-center gap-2"><CircleNotch size={16} className="animate-spin" /> Perguntando à Nay quem é corretor…</p>
      ) : (
        <div className="rounded-2xl border border-line bg-panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="border-b border-line">
              <tr>
                <Cabecalho col="nome" alinhar="left">Corretor</Cabecalho>
                <Cabecalho col="mensagensDele">Mensagens dele</Cabecalho>
                <Cabecalho col="visitasPedidas">Visitas pedidas</Cabecalho>
                <Cabecalho col="visitasRealizadas">Realizadas</Cabecalho>
                <Cabecalho col="documentos">Documentos</Cabecalho>
                <Cabecalho col="ultimaMensagem">Última mensagem</Cabecalho>
              </tr>
            </thead>
            <tbody>
              {linhas.map((c) => (
                <FragmentoDaLinha key={c.leadId} c={c} aberto={aberto === c.leadId} aoAbrir={() => setAberto((a) => a === c.leadId ? null : c.leadId)} />
              ))}
              {!linhas.length && (
                <tr><td colSpan={6} className="px-3 py-8 text-center text-muted">Nenhum corretor {busca ? 'com essa busca' : 'ainda'}.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

function FragmentoDaLinha({ c, aberto, aoAbrir }: { c: Corretor; aberto: boolean; aoAbrir: () => void }) {
  const etapa = c.etapa ? ETAPA_DA_NAY[c.etapa] : null
  return (
    <>
      <tr className="border-b border-line/60 hover:bg-graphite-6/20">
        <td className="px-3 py-2.5">
          <div className="flex items-center gap-2.5 min-w-0">
            <span className="w-9 h-9 rounded-full overflow-hidden bg-graphite-6/40 flex-shrink-0">
              {c.avatar && <img src={c.avatar} alt="" className="w-full h-full object-cover" loading="lazy" />}
            </span>
            <span className="min-w-0">
              <Link href={linkDaConversa(c.leadId).replace('/chat?', '/chat/parceria?')} className="font-semibold text-ink hover:underline inline-flex items-center gap-1">
                {c.nome} <ChatCircleText size={14} className="text-muted" />
              </Link>
              <span className="block text-xs text-muted">
                {c.creci ? `CRECI ${c.creci} · ` : ''}<CopiarNumero telefone={c.telefone} />
                {etapa && <span className="ml-1.5 px-1 rounded-[3px] text-[10.5px] font-semibold" style={{ color: etapa.cor, border: `1px solid ${etapa.cor}66` }}>{etapa.rotulo}</span>}
              </span>
            </span>
          </div>
        </td>
        <td className="px-3 py-2.5 text-right tabular-nums">
          <span className="font-semibold text-ink">{c.mensagensDele}</span>
          <span className="block text-xs text-muted">{c.mensagensNossas} nossas</span>
        </td>
        <td className="px-3 py-2.5 text-right tabular-nums font-semibold text-ink">
          {c.visitasPedidas}{c.visitasAbertas ? <span className="block text-xs font-normal text-muted">{c.visitasAbertas} em andamento</span> : null}
        </td>
        <td className="px-3 py-2.5 text-right tabular-nums text-ink">{c.visitasRealizadas}</td>
        <td className="px-3 py-2.5 text-right">
          <button type="button" onClick={aoAbrir} className="inline-flex items-center gap-1 text-ink-2 hover:text-ink" aria-expanded={aberto}>
            <FolderSimple size={16} /> {c.documentos} {aberto ? <CaretUp size={11} /> : <CaretDown size={11} />}
          </button>
        </td>
        <td className="px-3 py-2.5 text-right text-ink-2 whitespace-nowrap">{quando(c.ultimaMensagem)}</td>
      </tr>
      {aberto && (
        <tr className="border-b border-line/60 bg-graphite-6/10">
          <td colSpan={6} className="px-4"><Pasta leadId={c.leadId} /></td>
        </tr>
      )}
    </>
  )
}
