'use client'

/**
 * IMÓVEIS CAPTAR OLX (Pedro, 03/11/2026): "Analisa nossa banca de imóveis da olx, quero que retire uma lista e ponha lá no
 * menu do crm IMOVEIS CAPTAR OLX que vai ser só imóveis com alta probabilidade de serem de proprietários e não de corretores
 * ... e separa lá uma lista de contatos com um botão chamar no WhatsApp e outro chamar na OLX (o botão chamar no WhatsApp já
 * vem preenchido com a mensagem perguntando se o imóvel está disponível que nem a Nay manda hoje quando vai buscar para um lead)".
 *
 * Lê /api/imoveis-captar-olx (585). Cada cartão: o anúncio, a nota de dono (0-100) com os sinais, e os dois botões. O WhatsApp
 * abre a conversa no WhatsApp de quem clicou com a pergunta da Nay digitada (lib/perguntaAoAnunciante); a OLX abre o anúncio,
 * onde fica o "Chat". O clique fica anotado (quem e quando) e o cartão desce para "Já chamados".
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowsClockwise, CircleNotch, HouseLine, WhatsappLogo, ArrowSquareOut, CaretDown, CaretUp, CheckCircle } from '@phosphor-icons/react'
import { perguntaAoAnunciante } from '@/lib/perguntaAoAnunciante'

interface Item {
  olx_id: number; url: string; titulo: string | null; preco: number | null; preco_texto: string | null; tipo_negocio: string | null
  categoria: string | null; bairro: string | null; quartos: number | null; area_m2: number | null; foto: string | null; n_fotos: number | null
  anunciante: string | null; telefone: string | null; telefones: string[]; whatsapp: boolean | null; descricao: string | null
  publicado_em: string | null; nota: number; sinais: string[]; chamado_em: string | null; chamado_por: string | null; chamado_como: string | null
}

function fone(v: string) {
  const d = (v || '').replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : v
}
const com55 = (v: string) => { const d = (v || '').replace(/\D/g, ''); return d.length === 10 || d.length === 11 ? '55' + d : d }
const dia = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', year: '2-digit' }) : '')
const quando = (iso: string | null) => (iso ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '')
const corDaNota = (n: number) => (n >= 90 ? '#16a34a' : n >= 80 ? '#65a30d' : '#d97706')
const negocio = (i: Item) => (/aluguel/i.test(i.tipo_negocio || '') ? 'aluguel' : 'venda')
const POR_PAGINA = 60

function Cartao({ i, onChamar }: { i: Item; onChamar: (i: Item, como: 'whatsapp' | 'olx') => void }) {
  const [aberto, setAberto] = useState(false)
  const texto = perguntaAoAnunciante(i)
  const wa = i.telefone ? `https://wa.me/${com55(i.telefone)}?text=${encodeURIComponent(texto)}` : null
  return (
    <div className={`rounded-lg border border-line bg-panel p-3 flex gap-3 ${i.chamado_em ? 'opacity-70' : ''}`}>
      {i.foto
        ? <a href={i.url} target="_blank" rel="noreferrer" className="shrink-0"><img src={i.foto} alt="" loading="lazy" className="w-24 h-24 sm:w-32 sm:h-28 object-cover rounded-md bg-black/5" /></a>
        : <div className="shrink-0 w-24 h-24 sm:w-32 sm:h-28 rounded-md bg-black/5 dark:bg-white/10 flex items-center justify-center text-muted"><HouseLine size={28} /></div>}
      <div className="min-w-0 flex-1 flex flex-col gap-1.5">
        <div className="flex items-start justify-between gap-2 flex-wrap">
          <div className="min-w-0">
            <div className="font-semibold leading-snug">{i.titulo || 'Sem título'}</div>
            <div className="text-xs text-muted">
              {[i.preco_texto, negocio(i), i.bairro, i.quartos ? `${i.quartos} qto(s)` : null, i.area_m2 ? `${i.area_m2} m²` : null].filter(Boolean).join(' · ')}
            </div>
          </div>
          <span title={i.sinais.join('\n')} className="px-2.5 py-1 rounded-full text-xs font-bold shrink-0"
                style={{ color: corDaNota(i.nota), background: `color-mix(in srgb, ${corDaNota(i.nota)} 14%, transparent)`, border: `1px solid color-mix(in srgb, ${corDaNota(i.nota)} 35%, transparent)` }}>
            Dono {i.nota}%
          </span>
        </div>
        <div className="text-sm">
          <b>{i.anunciante || 'Sem nome'}</b>
          {i.telefone ? <span className="text-muted"> · {fone(i.telefone)}{i.telefones.length > 1 ? ` (+${i.telefones.length - 1})` : ''}</span> : <span className="text-muted"> · sem telefone no anúncio</span>}
          {i.publicado_em && <span className="text-muted"> · anunciado em {dia(i.publicado_em)}</span>}
        </div>
        <div className="flex flex-wrap gap-1 text-[11px]">
          {i.sinais.map((s) => <span key={s} className="px-1.5 py-0.5 rounded border border-line text-muted">{s}</span>)}
        </div>
        {i.chamado_em && (
          <div className="text-xs flex items-center gap-1" style={{ color: '#16a34a' }}>
            <CheckCircle size={14} weight="fill" /> Chamado {i.chamado_como === 'olx' ? 'na OLX' : 'no WhatsApp'} por {i.chamado_por} em {quando(i.chamado_em)}
          </div>
        )}
        <div className="flex flex-wrap items-center gap-2 mt-0.5">
          {wa ? (
            <a href={wa} target="_blank" rel="noreferrer" onClick={() => onChamar(i, 'whatsapp')}
               className="flex items-center gap-1.5 px-3 py-1.5 rounded-md text-white text-sm font-medium hover:opacity-90" style={{ background: '#25d366' }}>
              <WhatsappLogo size={16} weight="bold" /> Chamar no WhatsApp
            </a>
          ) : (
            <span className="flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-line text-sm text-muted cursor-not-allowed" title="O anúncio não traz o telefone: chame pela OLX">
              <WhatsappLogo size={16} /> Sem telefone
            </span>
          )}
          <a href={i.url} target="_blank" rel="noreferrer" onClick={() => onChamar(i, 'olx')}
             className="flex items-center gap-1.5 px-3 py-1.5 rounded-md text-white text-sm font-medium hover:opacity-90" style={{ background: '#6e0ad6' }}>
            <ArrowSquareOut size={16} weight="bold" /> Chamar na OLX
          </a>
          <button type="button" onClick={() => setAberto((v) => !v)} className="flex items-center gap-1 text-xs text-accent hover:underline">
            {aberto ? <CaretUp size={12} /> : <CaretDown size={12} />} {aberto ? 'Esconder' : 'Ver'} a descrição e a mensagem
          </button>
        </div>
        {aberto && (
          <div className="flex flex-col gap-2 text-sm">
            <div className="whitespace-pre-wrap rounded-md bg-black/5 dark:bg-white/5 p-2 text-xs max-h-60 overflow-y-auto">{i.descricao || '(sem descrição)'}</div>
            <div className="rounded-md border border-line p-2 text-xs whitespace-pre-wrap"><b>Mensagem do WhatsApp:</b>{'\n'}{texto}</div>
          </div>
        )}
      </div>
    </div>
  )
}

export default function ImoveisCaptarOlxPage() {
  const [dados, setDados] = useState<{ itens: Item[]; fora: Record<string, number>; carregadoEm: string | null; analisados: number } | null>(null)
  const [erro, setErro] = useState('')
  const [carregando, setCarregando] = useState(false)
  const [aba, setAba] = useState<'com_tel' | 'sem_tel' | 'chamados'>('com_tel')
  const [neg, setNeg] = useState<'' | 'venda' | 'aluguel'>('')
  const [busca, setBusca] = useState('')
  const [mostrar, setMostrar] = useState(POR_PAGINA)
  const [verFora, setVerFora] = useState(false)

  const carregar = useCallback(() => {
    setCarregando(true); setErro('')
    fetch('/api/imoveis-captar-olx').then(async (r) => {
      const j = await r.json()
      if (!r.ok) throw new Error(j.error || j.message || 'Erro')
      setDados(j)
    }).catch((e) => setErro(e.message || 'Não consegui ler a lista.')).finally(() => setCarregando(false))
  }, [])
  useEffect(() => { carregar() }, [carregar])
  useEffect(() => { setMostrar(POR_PAGINA) }, [aba, neg, busca])

  const chamar = useCallback((i: Item, como: 'whatsapp' | 'olx') => {
    if (i.chamado_em) return
    fetch('/api/imoveis-captar-olx', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ olx_id: i.olx_id, como }) })
      .then((r) => r.json()).then((j) => {
        if (!j.ok) return
        setDados((d) => d && { ...d, itens: d.itens.map((x) => x.olx_id === i.olx_id ? { ...x, chamado_em: new Date().toISOString(), chamado_por: j.quem, chamado_como: como } : x) })
      }).catch(() => {})
  }, [])

  const filtrados = useMemo(() => {
    const t = busca.trim().toLowerCase()
    return (dados?.itens || []).filter((i) => (!neg || negocio(i) === neg)
      && (!t || [i.titulo, i.bairro, i.anunciante, i.categoria].some((x) => (x || '').toLowerCase().includes(t))))
  }, [dados, neg, busca])
  const grupos = useMemo(() => ({
    com_tel: filtrados.filter((i) => !i.chamado_em && i.telefone),
    sem_tel: filtrados.filter((i) => !i.chamado_em && !i.telefone),
    chamados: filtrados.filter((i) => i.chamado_em).sort((p, q) => (q.chamado_em || '').localeCompare(p.chamado_em || '')),
  }), [filtrados])
  const visiveis = grupos[aba]
  const totalFora = Object.values(dados?.fora || {}).reduce((s, n) => s + n, 0)

  return (
    <div className="p-4 md:p-6 max-w-5xl mx-auto flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div className="flex items-center gap-2">
          <HouseLine size={22} weight="duotone" />
          <h1 className="text-xl font-bold">Imóveis captar OLX</h1>
        </div>
        <button type="button" onClick={carregar} disabled={carregando} className="flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-line text-sm hover:bg-black/5 dark:hover:bg-white/10">
          {carregando ? <CircleNotch size={14} className="animate-spin" /> : <ArrowsClockwise size={14} />} Atualizar
        </button>
      </div>
      <p className="text-sm text-muted">
        Anúncios de particular da OLX em Manaus com cara de dono. Saíram os corretores e proprietários que já conhecemos, quem já falou com a gente
        por qualquer número ou já está no CRM, quem tem CRECI, imobiliária ou código de imobiliária no anúncio e quem tem 3 ou mais imóveis.
        A nota diz a chance de ser o dono. O botão do WhatsApp abre a conversa com a pergunta da Nay já digitada; o da OLX abre o anúncio (o chat fica nele).
      </p>
      {dados && (
        <div className="text-xs text-muted">
          {dados.analisados} anúncios analisados{dados.carregadoEm ? ` (lista de ${dia(dados.carregadoEm)})` : ''} · {dados.itens.length} na lista · {totalFora} fora{' '}
          <button type="button" className="text-accent hover:underline" onClick={() => setVerFora((v) => !v)}>{verFora ? 'esconder' : 'ver por quê'}</button>
          {verFora && (
            <div className="mt-1 flex flex-wrap gap-1">
              {Object.entries(dados.fora).sort((a, b) => b[1] - a[1]).map(([m, n]) => <span key={m} className="px-1.5 py-0.5 rounded border border-line">{m}: {n}</span>)}
            </div>
          )}
        </div>
      )}
      <div className="flex gap-2 flex-wrap items-center">
        {([['com_tel', 'Com telefone'], ['sem_tel', 'Só pela OLX'], ['chamados', 'Já chamados']] as const).map(([k, r]) => (
          <button key={k} type="button" onClick={() => setAba(k)}
                  className={`px-3 py-1.5 rounded-full text-sm border ${aba === k ? 'bg-accent text-white border-accent' : 'border-line hover:bg-black/5 dark:hover:bg-white/10'}`}>
            {r} · {grupos[k].length}
          </button>
        ))}
        <select value={neg} onChange={(e) => setNeg(e.target.value as any)} className="px-2 py-1.5 rounded-md border border-line bg-panel text-sm">
          <option value="">Venda e aluguel</option><option value="venda">Venda</option><option value="aluguel">Aluguel</option>
        </select>
        <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Bairro, título, nome…"
               className="px-2 py-1.5 rounded-md border border-line bg-panel text-sm flex-1 min-w-[160px]" />
      </div>
      {erro && <div className="rounded-md border border-red-500/40 bg-red-500/10 text-red-600 px-3 py-2 text-sm">{erro}</div>}
      {!dados && !erro && <div className="flex items-center gap-2 text-muted"><CircleNotch size={16} className="animate-spin" /> Carregando…</div>}
      {dados && visiveis.length === 0 && <div className="text-muted text-sm">Nenhum anúncio aqui.</div>}
      <div className="flex flex-col gap-3">{visiveis.slice(0, mostrar).map((i) => <Cartao key={i.olx_id} i={i} onChamar={chamar} />)}</div>
      {visiveis.length > mostrar && (
        <button type="button" onClick={() => setMostrar((m) => m + POR_PAGINA)} className="self-center px-4 py-2 rounded-md border border-line text-sm hover:bg-black/5 dark:hover:bg-white/10">
          Mostrar mais ({visiveis.length - mostrar})
        </button>
      )}
    </div>
  )
}
