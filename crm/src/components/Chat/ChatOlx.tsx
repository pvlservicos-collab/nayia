'use client'

/**
 * AS CONSULTAS DO BOT DA OLX (Pedro, 08/10/2026). Nasceu como a aba Chat OLX inteira; no mesmo dia a aba virou o
 * chat das duas contas (ChatOlxContas.tsx) e isto ficou atrás do botão "Consultas do bot".
 *
 * O bot da OLX acha um anúncio, pergunta ao nosso sistema o que fazer e recebe "fechar" ou "abordar" com a
 * mensagem para mandar ao anunciante (webhook de consulta, migração 309). Aqui fica o que ele já consultou, no
 * formato das outras abas de conversa: à esquerda os anúncios (o mais recente primeiro), à direita o anúncio
 * e a mensagem que saiu para ele mandar.
 *
 * O QUE ESTA TELA NÃO SABE: se o bot mandou mesmo a mensagem, e o que o anunciante respondeu. A conversa
 * acontece no chat da OLX e o bot ainda não devolve nada disso. Por isso o balão diz "entregue ao bot", não
 * "enviada", e o botão abre o anúncio na OLX para quem quiser ver a conversa lá.
 *
 * Só leitura: /api/olx/abordagens, relido a cada minuto.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowClockwise, ArrowLeft, ArrowSquareOut, ChatsCircle, CircleNotch, Copy, MagnifyingGlass, X } from '@phosphor-icons/react'
import { MOTIVO_OLX, type AbordagemOlx } from '@/lib/olxAbordagens'

type Filtro = 'abordar' | 'fechar' | 'todos'

const FUSO = 'America/Manaus'
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
const diaDe = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: FUSO })
const horaDe = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' })
/** na lista: a hora se foi hoje, senão o dia */
function quandoCurto(iso: string) {
  return diaDe(iso) === diaDe(new Date().toISOString())
    ? horaDe(iso)
    : new Date(iso).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })
}
const quandoInteiro = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
const dinheiro = (v: number | null) => (v == null ? null : v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 }))
const quandoDa = (a: AbordagemOlx) => a.entregueEm || a.recebidoEm
const nomeDe = (a: AbordagemOlx) => a.anunciante || 'Anunciante sem nome'
const linkSeguro = (l: string) => (/^https?:\/\//i.test(l) ? l : null)

function Selo({ a }: { a: AbordagemOlx }) {
  const abordado = a.acao === 'abordar'
  const cor = abordado ? '#16a34a' : '#64748b'
  return (
    <span className="inline-flex items-center rounded-full px-1.5 py-[1px] text-[11px] font-semibold flex-shrink-0"
          style={{ background: cor + '22', color: cor }}>
      {abordado ? 'abordado' : 'fechado'}
    </span>
  )
}

export default function ChatOlx() {
  const [lista, setLista] = useState<AbordagemOlx[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [filtro, setFiltro] = useState<Filtro>('abordar')
  const [selId, setSelId] = useState<number | null>(null)
  const [copiado, setCopiado] = useState(false)

  const carregar = useCallback(() => {
    fetch('/api/olx/abordagens')
      .then(async (r) => {
        const j = await r.json().catch(() => ({}))
        if (!r.ok) throw new Error(j?.error || `Erro ${r.status}`)
        setLista(Array.isArray(j.abordagens) ? j.abordagens : [])
        setErro(null)
      })
      .catch((e) => setErro(e.message || 'Não consegui ler.'))
  }, [])
  useEffect(() => { carregar(); const t = setInterval(carregar, 60_000); return () => clearInterval(t) }, [carregar])
  useEffect(() => { setCopiado(false) }, [selId])

  const conta = useMemo(() => {
    const l = lista || []
    const hoje = diaDe(new Date().toISOString())
    return {
      abordar: l.filter((a) => a.acao === 'abordar').length,
      fechar: l.filter((a) => a.acao === 'fechar').length,
      todos: l.length,
      hoje: l.filter((a) => a.acao === 'abordar' && diaDe(quandoDa(a)) === hoje).length,
    }
  }, [lista])

  const filtrados = useMemo(() => {
    const q = sem(busca.trim())
    return (lista || []).filter((a) =>
      (filtro === 'todos' || a.acao === filtro) &&
      (!q || sem([a.anunciante, a.titulo, a.bairro, a.condominio, a.codigo].filter(Boolean).join(' ')).includes(q)))
  }, [lista, busca, filtro])

  const sel = useMemo(() => (lista || []).find((a) => a.id === selId) || null, [lista, selId])

  async function copiar(texto: string) {
    try { await navigator.clipboard.writeText(texto); setCopiado(true) } catch { setCopiado(false) }
  }

  const listaHtml = (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-panel)' }}>
      <div className="wa-topo justify-between gap-2">
        <span className="text-[16px] font-semibold flex items-center gap-2" style={{ color: 'var(--wa-text)' }}>
          <ChatsCircle size={22} /> Consultas do bot
          {lista && <span className="text-[13px] font-normal" style={{ color: 'var(--wa-text-2)' }}>{conta.hoje} abordados hoje</span>}
        </span>
        <button type="button" className="wa-icone-btn" onClick={carregar} title="Atualizar agora"><ArrowClockwise size={20} /></button>
      </div>
      <div className="px-3 pb-2 pt-2">
        <label className="wa-busca"><MagnifyingGlass size={18} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Procurar anunciante, anúncio ou bairro" aria-label="Procurar" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <div className="flex flex-wrap gap-1.5 mt-2">
          {([['abordar', 'Abordados'], ['fechar', 'Fechados'], ['todos', 'Todos']] as [Filtro, string][]).map(([f, r]) => (
            <button key={f} type="button" onClick={() => setFiltro(f)} className={`wa-chip ${filtro === f ? 'wa-chip--on' : ''}`}>
              {r}{lista ? ` ${conta[f]}` : ''}
            </button>
          ))}
        </div>
      </div>
      <div className="flex-1 overflow-y-auto wa-rolagem">
        {!lista && !erro && (
          <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}>
            <CircleNotch size={18} className="animate-spin" /> Lendo os anúncios…
          </p>
        )}
        {erro && <p className="text-center text-[14px] mt-10 px-6 text-red-500">{erro}</p>}
        {filtrados.map((a) => (
          <button key={a.id} type="button" onClick={() => setSelId(a.id)}
                  className={`wa-linha w-full text-left ${selId === a.id ? 'wa-linha--sel' : ''}`}>
            <span className="w-[49px] h-[49px] mx-2 rounded-full grid place-items-center flex-shrink-0"
                  style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-icon)' }}><ChatsCircle size={24} /></span>
            <span className="flex-1 min-w-0 py-2.5 pr-3" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
              <span className="flex items-center gap-2">
                <span className="flex-1 truncate text-[15.5px]" style={{ color: 'var(--wa-text)' }}>{nomeDe(a)}</span>
                <span className="text-[11.5px] flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>{quandoCurto(quandoDa(a))}</span>
              </span>
              <span className="block truncate text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{a.titulo || 'Anúncio sem título'}</span>
              <span className="flex items-center gap-1.5 mt-0.5">
                <span className="flex-1 truncate text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                  {[a.bairro, dinheiro(a.preco)].filter(Boolean).join(' · ') || '—'}
                </span>
                <Selo a={a} />
              </span>
            </span>
          </button>
        ))}
        {lista && !filtrados.length && (
          <p className="text-center text-[14px] mt-8 px-6" style={{ color: 'var(--wa-text-2)' }}>
            {lista.length ? 'Nenhum anúncio assim.' : 'O bot da OLX ainda não consultou nenhum anúncio.'}
          </p>
        )}
      </div>
    </div>
  )

  const link = sel ? linkSeguro(sel.link) : null
  const detalhe = !sel ? (
    <div className="h-full flex flex-col items-center justify-center gap-2 px-8 text-center" style={{ background: 'var(--wa-conv-bg)' }}>
      <ChatsCircle size={48} style={{ color: 'var(--wa-text-2)' }} />
      <p className="text-[15px]" style={{ color: 'var(--wa-text)' }}>Escolha um anúncio para ver a mensagem que saiu para o anunciante.</p>
      <p className="text-[13px] max-w-md" style={{ color: 'var(--wa-text-2)' }}>
        Aqui aparece o que o bot da OLX consultou. A conversa em si acontece no chat da OLX.
      </p>
    </div>
  ) : (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-conv-bg)' }}>
      <div className="wa-topo gap-2">
        <button type="button" className="wa-icone-btn md:hidden" onClick={() => setSelId(null)} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <div className="flex-1 min-w-0">
          <p className="truncate text-[16px] font-semibold" style={{ color: 'var(--wa-text)' }}>{nomeDe(sel)}</p>
          <p className="text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>{sel.titulo || 'Anúncio sem título'}</p>
        </div>
        {link && (
          <a href={link} target="_blank" rel="noopener noreferrer" className="wa-chip inline-flex items-center gap-1.5 flex-shrink-0"
             title="Abre o anúncio na OLX, em outra aba">
            <ArrowSquareOut size={15} /> Abrir na OLX
          </a>
        )}
      </div>

      <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-4 flex flex-col gap-3">
        {/* o anúncio */}
        <div className="self-center w-full max-w-xl rounded-xl px-4 py-3 text-[13.5px] shadow-sm" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)' }}>
          <p className="font-semibold text-[14.5px]">{sel.titulo || 'Anúncio sem título'}</p>
          <p className="mt-1" style={{ color: 'var(--wa-text-2)' }}>
            {[sel.tipo, sel.finalidade, dinheiro(sel.preco), sel.bairro, sel.condominio].filter(Boolean).join(' · ') || 'Sem dados do anúncio'}
          </p>
          <p className="mt-1" style={{ color: 'var(--wa-text-2)' }}>
            Anunciante: {nomeDe(sel)}{sel.telefone ? ` · ${sel.telefone}` : ''}
          </p>
          <p className="mt-1" style={{ color: 'var(--wa-text-2)' }}>
            Consultado em {quandoInteiro(sel.recebidoEm)}{sel.pedidos > 1 ? ` · o bot perguntou ${sel.pedidos} vezes` : ''}
          </p>
        </div>

        {sel.acao === 'abordar' && sel.mensagem ? (
          <>
            <div className="self-end max-w-[78%] rounded-lg px-3 py-2 text-[14px] shadow-sm"
                 style={{ background: 'var(--wa-out)', color: 'var(--wa-out-ink)' }}>
              <p className="whitespace-pre-wrap break-words">{sel.mensagem}</p>
              <p className="mt-1 text-right text-[11px] opacity-70">
                entregue ao bot {sel.entregueEm ? quandoInteiro(sel.entregueEm) : ''}
              </p>
            </div>
            <div className="self-end flex items-center gap-2">
              <button type="button" className="wa-chip inline-flex items-center gap-1.5" onClick={() => void copiar(sel.mensagem!)}>
                <Copy size={14} /> {copiado ? 'Copiada' : 'Copiar a mensagem'}
              </button>
            </div>
            <p className="self-center max-w-xl text-center text-[12.5px] rounded-lg px-3 py-2" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text-2)' }}>
              O bot recebeu este texto para mandar no chat da OLX. A resposta do anunciante fica na OLX e ainda não chega aqui.
            </p>
          </>
        ) : (
          <p className="self-center max-w-xl text-center text-[13px] rounded-lg px-3 py-2" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)' }}>
            Fechado sem mensagem: {(MOTIVO_OLX[sel.motivo] || sel.motivo).toLowerCase()}
            {sel.codigo ? ` (imóvel ${sel.codigo})` : ''}.
          </p>
        )}
      </div>
    </div>
  )

  return (
    <div className="flex flex-1 min-h-0 h-full">
      <div className={`flex-shrink-0 h-full min-h-0 ${selId ? 'hidden md:block' : 'w-full md:w-auto'}`}
           style={{ flexBasis: 'clamp(300px, 32%, 440px)', borderRight: '1px solid var(--wa-divider)' }}>
        {listaHtml}
      </div>
      <div className={`flex-1 min-w-0 h-full min-h-0 ${selId ? '' : 'hidden md:block'}`}>{detalhe}</div>
    </div>
  )
}
