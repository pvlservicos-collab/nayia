'use client'

/**
 * BUSCAR IMÓVEL OLX (Pedro, 19/10/2026: "constrói uma função para buscar esse imóvel fora lá no menu do CRM, Buscar
 * imóvel OLX, vai ter uns campos a preencher com os dados do lead, põe lá e ele segue o mesmo caminho").
 *
 * O formulário abre a MESMA ordem que a Nay do WhatsApp abre quando o catálogo não tem o imóvel (422 -> 416/421): busca
 * na OLX pela nota dos Grupos (88+), pergunta ao anunciante que já conhecemos (o "sim" vai direto ao cliente pelo 8595)
 * ou cria o pré-cadastro e avisa o grupo; quando o imóvel fica Disponível, a Nay manda ao cliente. Embaixo, as buscas
 * dos últimos dias e onde cada uma está. ?telefone=&nome= preenchem o cliente.
 */
import { Suspense, useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'next/navigation'

type Busca = {
  id: number; estado: string; teste: boolean; criado_em: string; atualizado_em: string; cliente: string; cliente_tel: string
  origem: string; filtros: Record<string, any>; nota: number | null; titulo: string | null; link: string | null; preco: string | null
  anunciante: string | null; contato: string | null; linha: string | null; resposta: string | null; codigo: number | null
  status_do_imovel: string | null; candidatos: number; erro: string | null
}

const ESTADOS: Record<string, { rotulo: string; cor: string }> = {
  pendente: { rotulo: 'Na fila', cor: '#64748b' },
  buscando: { rotulo: 'Buscando na OLX', cor: '#2563eb' },
  sem_navegador: { rotulo: 'Navegador do PC desligado', cor: '#b45309' },
  sem_resultado: { rotulo: 'Nada com nota 88+ na OLX', cor: '#b45309' },
  perguntado: { rotulo: 'Perguntei ao anunciante', cor: '#7c3aed' },
  confirmado: { rotulo: 'Anunciante confirmou: oferecido ao cliente', cor: '#16a34a' },
  negado: { rotulo: 'Anunciante disse que não está disponível', cor: '#dc2626' },
  sem_resposta: { rotulo: 'Anunciante não respondeu', cor: '#b45309' },
  no_grupo: { rotulo: 'No grupo da equipe', cor: '#b45309' },
  aguardando_cadastro: { rotulo: 'Pré-cadastro esperando aprovação', cor: '#0891b2' },
  enviado: { rotulo: 'Cadastrado e enviado ao cliente', cor: '#16a34a' },
  sem_cadastro: { rotulo: 'Pré-cadastro não foi aprovado', cor: '#64748b' },
  erro: { rotulo: 'Deu erro', cor: '#dc2626' },
  cancelado: { rotulo: 'Cancelada', cor: '#64748b' },
}

const CAMPO = 'w-full px-3 py-2 border border-line rounded-lg text-sm text-ink bg-transparent focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent'
const ROTULO = 'block text-xs font-semibold text-muted mb-1'

function fone(t: string | null | undefined) {
  let d = String(t || '').replace(/\D/g, '')
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2)
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : (t || '')
}
function quando(iso: string) {
  const d = new Date(iso)
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
}
function resumo(f: Record<string, any>) {
  return [f.finalidade === 'venda' ? 'venda' : 'locação', f.tipo,
          f.teto ? `até R$ ${Number(f.teto).toLocaleString('pt-BR')}` : '',
          (f.bairros || []).join(', ') || (f.qualquer_bairro ? 'qualquer bairro' : ''),
          f.quartos ? `${f.quartos} quartos` : '', f.aceita_escada === false ? 'com elevador' : '', f.mobilia]
    .filter(Boolean).join(' · ')
}

export default function BuscarImovelOlxPage() {
  return <Suspense fallback={null}><BuscarImovelOlx /></Suspense>
}

function BuscarImovelOlx() {
  const qs = useSearchParams()
  const [f, setF] = useState({
    nome: qs.get('nome') || '', telefone: qs.get('telefone') || '', finalidade: 'locacao', tipo: 'apartamento', teto: '',
    bairros: '', qualquer_bairro: false, quartos: '', aceita_menos_quartos: false, mobilia: '', precisa_elevador: false,
    financiamento: '', observacao: '',
  })
  const [enviando, setEnviando] = useState(false)
  const [recado, setRecado] = useState<{ t: string; ok?: boolean } | null>(null)
  const [buscas, setBuscas] = useState<Busca[]>([])
  const [carregando, setCarregando] = useState(true)

  const carregar = useCallback(async () => {
    try {
      const r = await fetch('/api/olx/busca-parceiro?dias=7')
      const j = await r.json()
      setBuscas(j.buscas || [])
    } finally { setCarregando(false) }
  }, [])
  useEffect(() => {
    void carregar()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void carregar() }, 20_000)
    return () => clearInterval(t)
  }, [carregar])

  const muda = (k: string, v: any) => setF((x) => ({ ...x, [k]: v }))

  const abrir = async (e: React.FormEvent) => {
    e.preventDefault()
    setEnviando(true)
    setRecado(null)
    try {
      const corpo = {
        ...f, teto: f.teto.replace(/\./g, '').replace(',', '.'),
        bairros: f.bairros.split(/[,;\n]/).map((b) => b.trim()).filter(Boolean),
        quartos: f.quartos || null, tipo: f.tipo || null, mobilia: f.mobilia || null, financiamento: f.financiamento || null,
      }
      const r = await fetch('/api/olx/busca-parceiro', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || j.erro) { setRecado({ t: j.erro || j.error || 'Não abriu a busca.' }); return }
      setRecado({ t: `Busca nº ${j.id} aberta. Ela roda pelo navegador do PC em alguns segundos: o andamento aparece aqui embaixo.`, ok: true })
      setF((x) => ({ ...x, teto: '', bairros: '', quartos: '', observacao: '' }))
      void carregar()
    } finally { setEnviando(false) }
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-6">
      <h1 className="text-2xl font-bold text-ink pb-1">Buscar imóvel OLX</h1>
      <p className="text-sm text-muted mb-5">
        Para o cliente que pediu um imóvel que não temos. A busca roda na OLX com a mesma nota da aba Grupos (só 88 ou mais).
        Se já falamos com o anunciante, ele é perguntado se está disponível e, com o sim, o imóvel vai ao cliente pelo
        WhatsApp Leads (8595). Se não, vira pré-cadastro em Imóveis › Aprovar imóveis e o grupo é avisado; quando vocês
        deixarem Disponível, a Nay manda ao cliente sozinha.
      </p>

      <form onSubmit={abrir} className="rounded-xl border border-line bg-panel p-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div className="sm:col-span-2"><label className={ROTULO}>Nome do cliente</label>
          <input className={CAMPO} value={f.nome} onChange={(e) => muda('nome', e.target.value)} placeholder="Ana Souza" /></div>
        <div className="sm:col-span-2"><label className={ROTULO}>WhatsApp do cliente *</label>
          <input className={CAMPO} value={f.telefone} onChange={(e) => muda('telefone', e.target.value)} placeholder="(92) 99999-9999" required inputMode="tel" /></div>
        <div><label className={ROTULO}>Negócio *</label>
          <select className={CAMPO} value={f.finalidade} onChange={(e) => muda('finalidade', e.target.value)}>
            <option value="locacao">Locação</option><option value="venda">Venda</option></select></div>
        <div><label className={ROTULO}>Tipo</label>
          <select className={CAMPO} value={f.tipo} onChange={(e) => muda('tipo', e.target.value)}>
            <option value="apartamento">Apartamento</option><option value="casa">Casa</option><option value="">Tanto faz</option></select></div>
        <div><label className={ROTULO}>Valor máximo (R$) *</label>
          <input className={CAMPO} value={f.teto} onChange={(e) => muda('teto', e.target.value)} placeholder="3.000" required inputMode="decimal" /></div>
        <div><label className={ROTULO}>Quartos</label>
          <input className={CAMPO} value={f.quartos} onChange={(e) => muda('quartos', e.target.value.replace(/\D/g, ''))} placeholder="2" inputMode="numeric" /></div>
        <div className="sm:col-span-2"><label className={ROTULO}>Bairros (separe por vírgula) *</label>
          <input className={CAMPO} value={f.bairros} onChange={(e) => muda('bairros', e.target.value)} placeholder="Parque 10, Adrianópolis"
                 disabled={f.qualquer_bairro} /></div>
        <div><label className={ROTULO}>Mobília</label>
          <select className={CAMPO} value={f.mobilia} onChange={(e) => muda('mobilia', e.target.value)}>
            <option value="">Tanto faz</option><option value="mobiliado">Mobiliado</option><option value="semi">Semimobiliado</option>
            <option value="sem">Sem mobília</option></select></div>
        <div><label className={ROTULO}>Financiamento</label>
          <select className={CAMPO} value={f.financiamento} onChange={(e) => muda('financiamento', e.target.value)}>
            <option value="">Não precisa</option><option value="simular">Vai simular</option><option value="aprovado">Já aprovado</option></select></div>
        <div className="sm:col-span-2 lg:col-span-4 flex flex-wrap gap-x-6 gap-y-2 text-sm text-ink">
          <label className="inline-flex items-center gap-2"><input type="checkbox" checked={f.qualquer_bairro} onChange={(e) => muda('qualquer_bairro', e.target.checked)} /> Qualquer bairro</label>
          <label className="inline-flex items-center gap-2"><input type="checkbox" checked={f.aceita_menos_quartos} onChange={(e) => muda('aceita_menos_quartos', e.target.checked)} /> Aceita um quarto a menos</label>
          <label className="inline-flex items-center gap-2"><input type="checkbox" checked={f.precisa_elevador} onChange={(e) => muda('precisa_elevador', e.target.checked)} /> Precisa de elevador</label>
        </div>
        <div className="sm:col-span-2 lg:col-span-4"><label className={ROTULO}>Observação para a equipe</label>
          <input className={CAMPO} value={f.observacao} onChange={(e) => muda('observacao', e.target.value)} placeholder="Ex.: perto da escola dos filhos" /></div>
        <div className="sm:col-span-2 lg:col-span-4 flex flex-wrap items-center gap-3">
          <button type="submit" className="btn btn-primary disabled:opacity-40" disabled={enviando}>{enviando ? 'Abrindo…' : 'Buscar na OLX'}</button>
          {recado && <span className="text-sm" style={{ color: recado.ok ? '#16a34a' : '#dc2626' }}>{recado.t}</span>}
        </div>
      </form>

      <div className="flex items-center justify-between mt-8 mb-3">
        <h2 className="text-lg font-semibold text-ink">Buscas dos últimos 7 dias</h2>
        <button type="button" className="btn btn-outline btn-sm" onClick={() => void carregar()}>Atualizar</button>
      </div>
      {carregando ? <p className="text-sm text-muted">Carregando…</p> : !buscas.length ? (
        <p className="text-sm text-muted">Nenhuma busca nos últimos 7 dias.</p>
      ) : (
        <div className="grid gap-3">
          {buscas.map((b) => {
            const e = ESTADOS[b.estado] || { rotulo: b.estado, cor: '#64748b' }
            return (
              <div key={b.id} className="rounded-xl border border-line bg-panel p-4 text-sm text-ink">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold">nº {b.id} · {b.cliente || 'sem nome'} · {fone(b.cliente_tel)}</span>
                  <span className="text-xs font-semibold rounded-full px-2 py-0.5 text-white" style={{ background: e.cor }}>{e.rotulo}</span>
                  {b.origem === 'manual' && <span className="text-xs text-muted">aberta pelo CRM</span>}
                  {b.teste && <span className="text-xs text-muted">teste</span>}
                  <span className="ml-auto text-xs text-muted">{quando(b.criado_em)}</span>
                </div>
                <p className="text-muted mt-1">{resumo(b.filtros || {})}</p>
                {b.titulo && (
                  <p className="mt-2">
                    {b.nota != null && <b>nota {Math.round(b.nota)} · </b>}
                    {b.link ? <a href={b.link} target="_blank" rel="noopener noreferrer" className="underline">{b.titulo}</a> : b.titulo}
                    {b.preco ? ` · ${b.preco}` : ''}
                  </p>
                )}
                {(b.anunciante || b.contato) && (
                  <p className="text-muted">Anunciante: {b.anunciante || 'sem nome'}{b.contato ? ` · ${fone(b.contato)}` : ''}
                    {b.linha ? ` · perguntado pela ${b.linha === 'parceria' ? 'Parceria' : 'Captação'}` : ''}</p>
                )}
                {b.resposta && <p className="text-muted">Respondeu: “{b.resposta}”</p>}
                {b.codigo && (
                  <p className="mt-1">Pré-cadastro <a className="underline" href={`/admin/imovel-editar.html?codigo=${b.codigo}`} target="_blank" rel="noopener noreferrer">#{b.codigo}</a>
                    {b.status_do_imovel ? ` (${b.status_do_imovel})` : ''} · aprovar em Imóveis › Aprovar imóveis</p>
                )}
                {b.erro && <p style={{ color: '#dc2626' }}>{b.erro}</p>}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
