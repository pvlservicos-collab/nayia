'use client'

/**
 * VISITAS AGENDADAS (Pedro, 29/09/2026): "uma aba só de visitas agendadas que
 * a ia preenche sozinha quando confirma uma visita e a Rayssa pode acompanhar
 * por lá o andamento, e as datas de tudo".
 *
 * Quem preenche é a Nay: cada visita que ela agenda aparece aqui sozinha (a
 * tela lê o banco dela a cada minuto -- /api/parceria/visitas). Para cada
 * uma: quando é, o imóvel, o corretor (com o atalho para a conversa dele), o
 * proprietário e o visitante, a situação de agora, a linha de passos com a
 * data de cada um (pedida, corretor confirmou, aprovada, proprietário OK,
 * André OK, confirmada, realizada) e, ao abrir, o andamento inteiro como a
 * Nay registrou.
 *
 * A AGENDA (Pedro, 29/09): "uma coluna na esquerda com a lista das visitas
 * como está hoje e na direita uma agenda real de dias". Clicar numa visita da
 * agenda abre o cartão dela na lista; clicar no cartão leva a agenda ao dia.
 * No celular as duas viram abas (Lista | Agenda). Todo horário é o de Manaus.
 *
 * O PAINEL DA VISITA (Pedro, 29/09): "quando eu clico na agenda da visita abre
 * ela em um popup à direita para eu excluir, marcar como realizada ou mudar, e
 * eu posso arrastar ela pela agenda, e também mudar o horário nesse popup".
 * As regras são dele e moram no banco da Nay (migração 169):
 *   - mudar o horário: NINGUÉM é avisado ("a pessoa manualmente faz isso");
 *   - realizada: a Nay pergunta ao corretor como foi (o pós-visita de sempre);
 *   - excluir: some da agenda e ninguém é avisado.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import dynamic from 'next/dynamic'
import {
  ArrowClockwise, CalendarCheck, ChatCircleText, CaretDown, CaretUp, MagnifyingGlass, X, CircleNotch, Warning,
  CheckCircle, Trash, Clock, PencilSimple, Check,
} from '@phosphor-icons/react'
import { useVisitasParceria, eventosDaVisita, mexerNaVisita } from '@/hooks/useVisitasParceria'
import type { Arrasto } from './AgendaDeVisitas'
import { ESTADO_DA_VISITA, EVENTO_DA_VISITA, type EventoDaVisita, type VisitaNaTela } from '@/lib/tiposNay'

// a agenda só existe no navegador (o FullCalendar mede a tela)
const AgendaDeVisitas = dynamic(() => import('./AgendaDeVisitas'), {
  ssr: false,
  loading: () => <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-text-2)' }}>Abrindo a agenda…</p>,
})

const FUSO = 'America/Manaus'
/** Manaus não tem horário de verão (desde 2000): o fuso é sempre -04:00. */
const OFFSET_DE_MANAUS = '-04:00'

/** Mesma regra da agenda (e o banco confere de novo): aberta e não realizada. */
function podeMudarHorario(v: VisitaNaTela) {
  return v.aberta && !['realizada', 'encerrada', 'cancelada', 'expirada'].includes(v.estado)
}

/** O horário da visita nos campos de data e hora, em Manaus. */
function paraCampos(iso: string | null) {
  if (!iso) return { data: '', hora: '' }
  const d = new Date(iso)
  return {
    data: d.toLocaleDateString('en-CA', { timeZone: FUSO }),
    hora: d.toLocaleTimeString('en-GB', { timeZone: FUSO, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }),
  }
}

/** A partir de 1024px a lista e a agenda ficam lado a lado. */
function useLadoALado() {
  const [lado, setLado] = useState(true)
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1024px)')
    const ver = () => setLado(mq.matches)
    ver()
    mq.addEventListener('change', ver)
    return () => mq.removeEventListener('change', ver)
  }, [])
  return lado
}

type Filtro = 'andamento' | 'encerradas' | 'todas'

const TOM: Record<string, string> = {
  andamento: 'var(--wa-tag-visita)',
  atencao: 'var(--wa-tag-prop)',
  ok: 'var(--wa-green)',
  fim: 'var(--wa-text-2)',
  ruim: 'var(--wa-tag-tel)',
}

const ACESSO: Record<string, string> = {
  chave_conosco: 'Chave com a gente',
  buscar_chave: 'Buscar a chave',
  fechadura: 'Fechadura eletrônica',
  proprietario_acompanha: 'O proprietário acompanha',
}

const AGUARDANDO: Record<string, string> = {
  corretor: 'o corretor', proprietario: 'o proprietário', motoboy: 'o André', tel: 'o Tel', equipe: 'a aprovação',
}

// Sempre no horário de Manaus: quem olha pode estar com o computador em Brasília.
function hora(iso: string | null) {
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: FUSO }) : '--:--'
}
function diaMes(iso: string | null) {
  return iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: FUSO }) : ''
}
function dataHora(iso: string | null) {
  if (!iso) return ''
  return `${diaMes(iso)} ${hora(iso)}`
}
/** O dia em Manaus, contado em dias desde 1970 (para "hoje", "amanhã"...). */
function diaEmManaus(d: Date) {
  const [a, m, dd] = d.toLocaleDateString('en-CA', { timeZone: FUSO }).split('-').map(Number)
  return Math.round(Date.UTC(a, m - 1, dd) / 86400000)
}
function nomeDoDia(iso: string | null): string {
  if (!iso) return 'Sem data'
  const d = new Date(iso)
  const dif = diaEmManaus(d) - diaEmManaus(new Date())
  if (dif === 0) return 'Hoje'
  if (dif === 1) return 'Amanhã'
  if (dif === -1) return 'Ontem'
  const s = d.toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: '2-digit', timeZone: FUSO })
  return s.charAt(0).toUpperCase() + s.slice(1)
}

/** Os passos da visita, com a data de cada um. */
function passos(v: VisitaNaTela) {
  const final = v.estado === 'cancelada' ? { rotulo: 'Cancelada', em: v.encerradaEm || v.atualizadoEm, ruim: true }
    : v.estado === 'expirada' ? { rotulo: 'Expirou', em: v.encerradaEm || v.atualizadoEm, ruim: true }
    : { rotulo: 'Realizada', em: v.estado === 'realizada' || v.estado === 'encerrada' ? (v.posVisitaEm || v.encerradaEm) : null, ruim: false }
  const precisaDoAndre = !!v.motoOkEm || v.estado === 'aguardando_motoboy' || v.acesso === 'chave_conosco' || v.acesso === 'buscar_chave'
  const lista = [
    { rotulo: 'Pedida', em: v.criadoEm },
    { rotulo: 'Corretor confirmou', em: v.confirmadaCorretorEm },
    { rotulo: v.aprovadaPor ? `Aprovada (${v.aprovadaPor})` : 'Aprovada', em: v.aprovadaEm },
    { rotulo: 'Proprietário OK', em: v.propOkEm },
    ...(precisaDoAndre ? [{ rotulo: 'André OK', em: v.motoOkEm }] : []),
    { rotulo: 'Confirmada', em: v.confirmadaEm },
  ].map((p) => ({ ...p, ruim: false }))
  return [...lista, final]
}

function Passos({ v }: { v: VisitaNaTela }) {
  const ps = passos(v)
  const atual = v.aberta ? ps.findIndex((p) => !p.em) : -1
  return (
    <ol className="flex flex-wrap items-start gap-x-1 gap-y-2 mt-3">
      {ps.map((p, i) => {
        const feito = !!p.em
        const cor = p.ruim && feito ? 'var(--wa-tag-tel)' : feito ? 'var(--wa-green)' : i === atual ? 'var(--wa-tag-visita)' : 'var(--wa-text-2)'
        return (
          <li key={i} className="flex items-start gap-1 min-w-[92px]">
            <span className="flex flex-col items-center">
              <span className="w-3.5 h-3.5 rounded-full mt-[3px] flex-shrink-0"
                    style={{ background: feito ? cor : 'transparent', border: `2px solid ${cor}`, opacity: feito || i === atual ? 1 : 0.5 }} />
            </span>
            <span className="leading-4">
              <span className="block text-[12.5px]" style={{ color: feito || i === atual ? 'var(--wa-text)' : 'var(--wa-text-2)', fontWeight: i === atual ? 600 : 400 }}>
                {p.rotulo}
              </span>
              <span className="block text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>{feito ? dataHora(p.em) : i === atual ? 'agora' : ''}</span>
            </span>
            {i < ps.length - 1 && <span className="hidden sm:block w-3 h-px mt-[10px]" style={{ background: 'var(--wa-divider)' }} />}
          </li>
        )
      })}
    </ol>
  )
}

function Andamento({ id }: { id: number }) {
  const [eventos, setEventos] = useState<EventoDaVisita[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  useEffect(() => {
    let vivo = true
    eventosDaVisita(id)
      .then((e) => { if (vivo) setEventos(e) })
      .catch((e) => { if (vivo) setErro(e?.message || 'erro') })
    return () => { vivo = false }
  }, [id])
  if (erro) return <p className="text-[13px] mt-2" style={{ color: 'var(--wa-tag-tel)' }}>Não consegui ler o andamento: {erro}</p>
  if (!eventos) return <p className="text-[13px] mt-2" style={{ color: 'var(--wa-text-2)' }}>Carregando o andamento…</p>
  if (!eventos.length) return <p className="text-[13px] mt-2" style={{ color: 'var(--wa-text-2)' }}>Sem registros.</p>
  return (
    <ul className="mt-3 border-l-2 pl-3 flex flex-col gap-1.5" style={{ borderColor: 'var(--wa-divider)' }}>
      {eventos.map((e, i) => (
        <li key={i} className="text-[13px] leading-[18px]">
          <span style={{ color: 'var(--wa-text-2)' }}>{dataHora(e.quando)} · </span>
          <span style={{ color: e.tipo.startsWith('mensagem_') ? 'var(--wa-text-2)' : 'var(--wa-text)' }}>
            {EVENTO_DA_VISITA[e.tipo] || e.tipo.replace(/_/g, ' ')}
          </span>
          {e.detalhe && <span style={{ color: 'var(--wa-text-2)' }}> — {e.detalhe}</span>}
        </li>
      ))}
    </ul>
  )
}

function CartaoDaVisita({ v, destacada, aoAbrirConversa, aoEscolher }: {
  v: VisitaNaTela; destacada: boolean; aoAbrirConversa: (leadId: string) => void; aoEscolher: (id: number) => void
}) {
  const [aberto, setAberto] = useState(destacada)
  // escolhida na agenda: abre o andamento dela
  useEffect(() => { if (destacada) setAberto(true) }, [destacada])
  const estado = ESTADO_DA_VISITA[v.estado] || { rotulo: v.estado, tom: 'fim' as const }
  const cor = TOM[estado.tom]
  return (
    <article id={`visita-${v.id}`} className="rounded-xl px-4 py-3.5 shadow-sm cursor-pointer"
             onClick={() => aoEscolher(v.id)}
             style={{ background: 'var(--wa-panel)', outline: destacada ? '2px solid var(--wa-green)' : 'none' }}>
      <div className="flex items-start gap-4">
        <div className="text-center flex-shrink-0 w-[62px]">
          <p className="text-[22px] leading-7 font-semibold tabular-nums" style={{ color: 'var(--wa-text)' }}>{hora(v.quando)}</p>
          <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{diaMes(v.quando)}</p>
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="text-[16px] leading-[21px] font-medium truncate" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>
              {v.imovel || (v.codigo ? `Imóvel ${v.codigo}` : 'Imóvel')}
            </h3>
            <span className="wa-marca" style={{ color: cor }}>{estado.rotulo}</span>
            {v.urgente && <span className="wa-marca" style={{ color: 'var(--wa-tag-tel)' }}><Warning size={11} weight="bold" /> Urgente</span>}
          </div>
          <div className="mt-1 text-[13.5px] leading-5 flex flex-wrap gap-x-4 gap-y-0.5" style={{ color: 'var(--wa-text-2)' }}>
            <span>
              Corretor: <span style={{ color: 'var(--wa-text)' }}>{v.corretorNome || v.conversa?.titulo || 'não identificado'}</span>
              {v.conversa && (
                <button type="button" onClick={(e) => { e.stopPropagation(); aoAbrirConversa(v.conversa!.leadId) }}
                        className="ml-2 inline-flex items-center gap-1 font-semibold hover:underline" style={{ color: 'var(--wa-green)' }}>
                  <ChatCircleText size={14} /> conversa
                </button>
              )}
            </span>
            {v.proprietarioNome && <span>Proprietário: <span style={{ color: 'var(--wa-text)' }}>{v.proprietarioNome}</span></span>}
            {v.visitanteNome && <span>Visitante: <span style={{ color: 'var(--wa-text)' }}>{v.visitanteNome}</span></span>}
            {v.acesso && <span>Acesso: <span style={{ color: 'var(--wa-text)' }}>{ACESSO[v.acesso] || v.acesso}</span></span>}
          </div>
          {v.aberta && v.aguardando && (
            <p className="mt-1 text-[13px]" style={{ color: cor }}>Esperando {AGUARDANDO[v.aguardando] || v.aguardando}.</p>
          )}
          {v.quandoSugerido && v.aberta && (
            <p className="mt-1 text-[13px]" style={{ color: 'var(--wa-tag-prop)' }}>Horário sugerido: {dataHora(v.quandoSugerido)}</p>
          )}
          {!v.aberta && (v.resultado || v.motivo) && (
            <p className="mt-1 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{v.resultado || v.motivo}</p>
          )}
          <Passos v={v} />
          <button type="button" onClick={(e) => { e.stopPropagation(); setAberto((a) => !a) }}
                  className="mt-2.5 inline-flex items-center gap-1 text-[13px] font-semibold" style={{ color: 'var(--wa-green)' }}>
            {aberto ? <CaretUp size={14} /> : <CaretDown size={14} />} {aberto ? 'Esconder o andamento' : 'Ver o andamento completo'}
          </button>
          {aberto && <Andamento id={v.id} />}
        </div>
      </div>
    </article>
  )
}

type Acao = 'horario' | 'realizada' | 'excluir' | 'editar'
type Edicao = { campo: string; valor: string | null }

/*
 * O LÁPIS (Pedro, 29/09: "quero poder alterar os itens da agenda lá
 * manualmente com um lapisinho se quiser"). Um campo por vez; o banco da Nay
 * confere (código tem que existir no catálogo) e anota no andamento quem
 * mudou o quê. Ninguém é avisado.
 */
function CampoEditavel({ rotulo, valor, exibir, opcoes, numerico, aoSalvar }: {
  rotulo: string
  valor: string | null
  exibir?: string | null
  opcoes?: Array<[string, string]>
  numerico?: boolean
  aoSalvar: (novo: string | null) => Promise<boolean>
}) {
  const [editando, setEditando] = useState(false)
  const [texto, setTexto] = useState(valor ?? '')
  const [salvando, setSalvando] = useState(false)
  useEffect(() => { if (!editando) setTexto(valor ?? '') }, [valor, editando])
  const salvar = async () => {
    setSalvando(true)
    const ok = await aoSalvar(texto.trim() ? texto.trim() : null)
    setSalvando(false)
    if (ok) setEditando(false)
  }
  if (!editando) {
    return (
      <span className="group/campo flex items-start gap-1.5">
        <span className="flex-1 min-w-0">
          {rotulo}: <span style={{ color: 'var(--wa-text)' }}>{exibir || valor || '—'}</span>
        </span>
        <button type="button" onClick={() => setEditando(true)} className="wa-icone-btn !w-6 !h-6 flex-shrink-0 opacity-70 hover:opacity-100"
                title={`Editar ${rotulo.toLowerCase()}`} aria-label={`Editar ${rotulo.toLowerCase()}`}>
          <PencilSimple size={14} />
        </button>
      </span>
    )
  }
  const estilo = { background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }
  return (
    <form className="flex items-center gap-1.5" onSubmit={(e) => { e.preventDefault(); void salvar() }}>
      <span className="flex-shrink-0">{rotulo}:</span>
      {opcoes ? (
        <select value={texto} onChange={(e) => setTexto(e.target.value)} className="flex-1 min-w-0 h-8 rounded-md px-2 text-[13.5px]" style={estilo} autoFocus>
          <option value="">(não definido)</option>
          {opcoes.map(([k, r]) => <option key={k} value={k}>{r}</option>)}
        </select>
      ) : (
        <input value={texto} onChange={(e) => setTexto(e.target.value)} inputMode={numerico ? 'numeric' : undefined}
               className="flex-1 min-w-0 h-8 rounded-md px-2 text-[13.5px]" style={estilo} autoFocus />
      )}
      <button type="submit" disabled={salvando} className="wa-icone-btn !w-7 !h-7" title="Salvar" aria-label="Salvar">
        {salvando ? <CircleNotch size={14} className="animate-spin" /> : <Check size={15} weight="bold" style={{ color: 'var(--wa-green)' }} />}
      </button>
      <button type="button" onClick={() => { setEditando(false); setTexto(valor ?? '') }} className="wa-icone-btn !w-7 !h-7" title="Cancelar" aria-label="Cancelar">
        <X size={14} />
      </button>
    </form>
  )
}

function PainelDaVisita({ v, aoFechar, aoAbrirConversa, aoMexer }: {
  v: VisitaNaTela
  aoFechar: () => void
  aoAbrirConversa: (leadId: string) => void
  aoMexer: (id: number, acao: Acao, quando?: string, edicao?: Edicao) => Promise<boolean>
}) {
  const [data, setData] = useState(() => paraCampos(v.quando).data)
  const [horaTxt, setHoraTxt] = useState(() => paraCampos(v.quando).hora)
  const [confirmar, setConfirmar] = useState<null | 'realizada' | 'excluir'>(null)
  const [andando, setAndando] = useState(false)
  useEffect(() => {
    const c = paraCampos(v.quando)
    setData(c.data); setHoraTxt(c.hora); setConfirmar(null)
  }, [v.id, v.quando])

  const estado = ESTADO_DA_VISITA[v.estado] || { rotulo: v.estado, tom: 'fim' as const }
  const cor = TOM[estado.tom]
  const mudavel = podeMudarHorario(v)
  const jaAconteceu = !!v.quando && new Date(v.quando).getTime() <= Date.now()
  const novo = data && horaTxt ? `${data}T${horaTxt}:00${OFFSET_DE_MANAUS}` : ''
  const mudou = !!novo && !isNaN(new Date(novo).getTime()) && new Date(novo).getTime() !== new Date(v.quando || 0).getTime()

  async function fazer(acao: Acao, quando?: string) {
    setAndando(true)
    await aoMexer(v.id, acao, quando)
    setAndando(false)
    setConfirmar(null)
  }

  const botao = 'inline-flex items-center justify-center gap-1.5 rounded-full px-4 h-9 text-[14px] font-medium disabled:opacity-45 disabled:cursor-not-allowed'
  return (
    <aside className="absolute inset-y-0 right-0 z-30 w-full sm:w-[400px] flex flex-col shadow-2xl"
           style={{ background: 'var(--wa-panel)', borderLeft: '1px solid var(--wa-divider)' }}
           aria-label={`Visita ${v.id}`}>
      <div className="flex items-start gap-2 px-4 pt-3.5 pb-3" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
        <div className="flex-1 min-w-0">
          <p className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Visita #{v.id}{v.codigo ? ` · código ${v.codigo}` : ''}</p>
          <h2 className="text-[17px] leading-[22px] font-semibold" style={{ color: 'var(--wa-text)', fontFamily: 'inherit' }}>
            {v.imovel || (v.codigo ? `Imóvel ${v.codigo}` : 'Imóvel')}
          </h2>
          <div className="mt-1 flex flex-wrap gap-1.5">
            <span className="wa-marca" style={{ color: cor }}>{estado.rotulo}</span>
            {v.urgente && <span className="wa-marca" style={{ color: 'var(--wa-tag-tel)' }}><Warning size={11} weight="bold" /> Urgente</span>}
          </div>
        </div>
        <button type="button" onClick={aoFechar} className="wa-icone-btn" title="Fechar" aria-label="Fechar"><X size={20} /></button>
      </div>

      <div className="flex-1 overflow-y-auto wa-rolagem px-4 py-3 flex flex-col gap-4">
        <section>
          <h3 className="text-[13px] font-semibold mb-1.5 flex items-center gap-1.5" style={{ color: 'var(--wa-text-2)', fontFamily: 'inherit' }}>
            <Clock size={15} /> Quando (horário de Manaus)
          </h3>
          {mudavel ? (
            <>
              <div className="flex gap-2">
                <input type="date" value={data} onChange={(e) => setData(e.target.value)} aria-label="Data da visita"
                       className="flex-1 min-w-0 h-10 rounded-lg px-3 text-[14px]"
                       style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)', colorScheme: 'light dark' }} />
                <input type="time" value={horaTxt} step={900} onChange={(e) => setHoraTxt(e.target.value)} aria-label="Hora da visita"
                       className="w-[112px] h-10 rounded-lg px-3 text-[14px]"
                       style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)', colorScheme: 'light dark' }} />
              </div>
              <button type="button" disabled={!mudou || andando} onClick={() => fazer('horario', novo)}
                      className={`${botao} mt-2 w-full`} style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
                {andando ? <CircleNotch size={16} className="animate-spin" /> : <Clock size={16} />} Salvar o novo horário
              </button>
              <p className="mt-1.5 text-[12.5px] leading-[17px]" style={{ color: 'var(--wa-text-2)' }}>
                Ninguém recebe mensagem: avise o corretor, o proprietário e o André se precisar. Os lembretes da Nay passam a
                seguir o horário novo. Dá também para arrastar a visita na agenda.
              </p>
            </>
          ) : (
            <p className="text-[14px]" style={{ color: 'var(--wa-text)' }}>
              {dataHora(v.quando) || 'Sem data'}
              <span className="block text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                {v.estado === 'realizada' ? 'Visita realizada' : 'Visita encerrada'}: o horário não muda mais.
              </span>
            </p>
          )}
          {v.quandoSugerido && v.aberta && (
            <p className="mt-1.5 text-[13px]" style={{ color: 'var(--wa-tag-prop)' }}>Horário sugerido: {dataHora(v.quandoSugerido)}</p>
          )}
        </section>

        <section className="text-[13.5px] leading-5 flex flex-col gap-0.5" style={{ color: 'var(--wa-text-2)' }}>
          <span>
            Corretor: <span style={{ color: 'var(--wa-text)' }}>{v.corretorNome || v.conversa?.titulo || 'não identificado'}</span>
            {v.conversa && (
              <button type="button" onClick={() => aoAbrirConversa(v.conversa!.leadId)}
                      className="ml-2 inline-flex items-center gap-1 font-semibold hover:underline" style={{ color: 'var(--wa-green)' }}>
                <ChatCircleText size={14} /> conversa
              </button>
            )}
          </span>
          <CampoEditavel rotulo="Imóvel (código)" valor={v.codigo != null ? String(v.codigo) : null} numerico
                         aoSalvar={(novo) => aoMexer(v.id, 'editar', undefined, { campo: 'codigo', valor: novo })} />
          <CampoEditavel rotulo="Visitante" valor={v.visitanteNome}
                         aoSalvar={(novo) => aoMexer(v.id, 'editar', undefined, { campo: 'visitante_nome', valor: novo })} />
          <CampoEditavel rotulo="Proprietário" valor={v.proprietarioNome}
                         aoSalvar={(novo) => aoMexer(v.id, 'editar', undefined, { campo: 'proprietario_nome', valor: novo })} />
          <CampoEditavel rotulo="Acesso" valor={v.acesso} exibir={v.acesso ? (ACESSO[v.acesso] || v.acesso) : null}
                         opcoes={Object.entries(ACESSO)}
                         aoSalvar={(novo) => aoMexer(v.id, 'editar', undefined, { campo: 'acesso', valor: novo })} />
          {v.aberta && v.aguardando && <span style={{ color: cor }}>Esperando {AGUARDANDO[v.aguardando] || v.aguardando}.</span>}
          {!v.aberta && (v.resultado || v.motivo) && <span>{v.resultado || v.motivo}</span>}
        </section>

        <section>
          <Passos v={v} />
          <h3 className="mt-4 text-[13px] font-semibold" style={{ color: 'var(--wa-text-2)', fontFamily: 'inherit' }}>Andamento</h3>
          <Andamento id={v.id} />
        </section>
      </div>

      <div className="px-4 py-3" style={{ borderTop: '1px solid var(--wa-divider)' }}>
        {confirmar ? (
          <div className="flex flex-col gap-2">
            <p className="text-[13.5px] leading-[19px]" style={{ color: 'var(--wa-text)' }}>
              {confirmar === 'realizada'
                ? 'Marcar como realizada? A Nay vai perguntar ao corretor como foi a visita.'
                : 'Excluir esta visita? Ela some da agenda e ninguém é avisado.'}
            </p>
            <div className="flex gap-2">
              <button type="button" disabled={andando} onClick={() => fazer(confirmar)}
                      className={`${botao} flex-1`}
                      style={confirmar === 'excluir'
                        ? { background: 'var(--wa-tag-tel)', color: '#fff' }
                        : { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
                {andando && <CircleNotch size={16} className="animate-spin" />}
                {confirmar === 'excluir' ? 'Excluir' : 'Marcar realizada'}
              </button>
              <button type="button" disabled={andando} onClick={() => setConfirmar(null)} className={`${botao} wa-chip`}>Voltar</button>
            </div>
          </div>
        ) : (
          <div className="flex gap-2">
            {mudavel && (
              <button type="button" disabled={!jaAconteceu} onClick={() => setConfirmar('realizada')}
                      title={jaAconteceu ? '' : 'A visita ainda não aconteceu'}
                      className={`${botao} flex-1`} style={{ background: 'var(--wa-chip-on-bg)', color: 'var(--wa-chip-on-ink)' }}>
                <CheckCircle size={17} /> Marcar como realizada
              </button>
            )}
            <button type="button" onClick={() => setConfirmar('excluir')}
                    className={`${botao} ${mudavel ? '' : 'flex-1'}`}
                    style={{ color: 'var(--wa-tag-tel)', border: '1px solid color-mix(in srgb, var(--wa-tag-tel) 45%, transparent)' }}>
              <Trash size={16} /> Excluir
            </button>
          </div>
        )}
      </div>
    </aside>
  )
}

export default function VisitasAgendadas({ aoAbrirConversa, destaque }: { aoAbrirConversa: (leadId: string) => void; destaque?: number | null }) {
  const { visitas, carregando, erro, recarregar } = useVisitasParceria(true)
  const [filtro, setFiltro] = useState<Filtro>('andamento')
  const [busca, setBusca] = useState('')
  const ladoALado = useLadoALado()
  const [modo, setModo] = useState<'lista' | 'agenda'>('lista')

  const abertas = visitas.filter((v) => v.aberta).length

  /* A visita escolhida -- pelo card do contato ("Ver o andamento em
     Visitas"), por um clique na agenda ou na lista. `pedido` conta os pedidos
     de rolar até ela: escolher a mesma de novo rola de novo. */
  const [selecionada, setSelecionada] = useState<number | null>(destaque ?? null)
  const [pedido, setPedido] = useState(destaque ? 1 : 0)
  useEffect(() => {
    if (destaque) { setSelecionada(destaque); setPedido((n) => n + 1) }
  }, [destaque])

  // a busca vale para a lista e para a agenda; a situação, só para a lista
  const buscadas = useMemo(() => {
    const q = busca.trim().toLowerCase()
    return visitas.filter((v) => !q || [v.imovel, v.codigo, v.corretorNome, v.conversa?.titulo, v.proprietarioNome, v.visitanteNome]
      .some((x) => String(x ?? '').toLowerCase().includes(q)))
  }, [visitas, busca])

  // o painel à direita: abre pelo clique na agenda ou no cartão da lista
  const [painel, setPainel] = useState<number | null>(null)
  const escolherNaAgenda = useCallback((id: number) => {
    setSelecionada(id)
    setPedido((n) => n + 1)
    setPainel(id)
  }, [])
  const escolherNaLista = useCallback((id: number) => { setSelecionada(id); setPainel(id) }, [])
  const visitaDoPainel = painel ? visitas.find((v) => v.id === painel) || null : null

  // o resultado de cada ação, embaixo da agenda por alguns segundos
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)
  useEffect(() => {
    if (!aviso) return
    const t = setTimeout(() => setAviso(null), aviso.ok ? 5000 : 9000)
    return () => clearTimeout(t)
  }, [aviso])

  const mexer = useCallback(async (id: number, acao: Acao, quando?: string, edicao?: Edicao) => {
    const r = await mexerNaVisita(id, acao, quando, edicao)
    setAviso({ ok: r.ok, texto: r.mensagem })
    await recarregar()
    if (r.ok && acao === 'excluir') setPainel(null)
    return r.ok
  }, [recarregar])

  // soltou a visita num horário novo: pergunta antes de gravar
  const [arrasto, setArrasto] = useState<Arrasto | null>(null)
  const [gravandoArrasto, setGravandoArrasto] = useState(false)
  const cancelarArrasto = useCallback(() => {
    arrasto?.reverter()
    setArrasto(null)
  }, [arrasto])
  const confirmarArrasto = useCallback(async () => {
    if (!arrasto) return
    setGravandoArrasto(true)
    const ok = await mexer(arrasto.visitaId, 'horario', arrasto.para)
    setGravandoArrasto(false)
    if (!ok) arrasto.reverter()
    setArrasto(null)
  }, [arrasto, mexer])
  useEffect(() => {
    const esc = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return
      if (arrasto) cancelarArrasto()
      else setPainel(null)
    }
    window.addEventListener('keydown', esc)
    return () => window.removeEventListener('keydown', esc)
  }, [arrasto, cancelarArrasto])
  const visitaDoArrasto = arrasto ? visitas.find((v) => v.id === arrasto.visitaId) : null

  // mostra e rola até a escolhida (se o filtro a esconde, passa para "Todas")
  const jaRolou = useRef(0)
  useEffect(() => {
    if (!selecionada || !pedido || jaRolou.current === pedido || !visitas.length) return
    const alvo = visitas.find((v) => v.id === selecionada)
    if (!alvo) return
    if ((!alvo.aberta && filtro === 'andamento') || (alvo.aberta && filtro === 'encerradas')) { setFiltro('todas'); return }
    jaRolou.current = pedido
    requestAnimationFrame(() => document.getElementById(`visita-${selecionada}`)?.scrollIntoView({ block: 'center', behavior: 'smooth' }))
  }, [selecionada, pedido, visitas, filtro, modo])

  const lista = useMemo(() => {
    const f = buscadas
      .filter((v) => (filtro === 'andamento' ? v.aberta : filtro === 'encerradas' ? !v.aberta : true))
    // as que vão acontecer: a mais próxima primeiro; as que passaram: a mais recente primeiro
    return f.sort((a, b) => {
      const ta = new Date(a.quando || a.criadoEm || 0).getTime()
      const tb = new Date(b.quando || b.criadoEm || 0).getTime()
      return filtro === 'andamento' ? ta - tb : tb - ta
    })
  }, [buscadas, filtro])

  const grupos: Array<{ dia: string; visitas: VisitaNaTela[] }> = []
  for (const v of lista) {
    const dia = nomeDoDia(v.quando || v.criadoEm)
    const g = grupos[grupos.length - 1]
    if (g && g.dia === dia) g.visitas.push(v)
    else grupos.push({ dia, visitas: [v] })
  }

  return (
    <div className="flex flex-col h-full min-w-0 flex-1" style={{ background: 'var(--wa-app)' }}>
      <div className="flex-shrink-0" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <div className="wa-topo gap-3">
          <CalendarCheck size={26} style={{ color: 'var(--wa-green)' }} />
          <div className="min-w-0">
            <h1 className="text-[20px] font-bold leading-6" style={{ color: 'var(--wa-text)' }}>Visitas agendadas</h1>
            <p className="text-[12.5px] leading-4" style={{ color: 'var(--wa-text-2)' }}>
              A Nay preenche sozinha: cada visita que ela agenda aparece aqui, com o andamento e as datas.
            </p>
          </div>
          <button type="button" onClick={() => void recarregar()} className="wa-icone-btn ml-auto" title="Atualizar agora">
            {carregando ? <CircleNotch size={20} className="animate-spin" /> : <ArrowClockwise size={20} />}
          </button>
        </div>
        <div className="flex flex-wrap items-center gap-2 px-4 pb-3">
          {!ladoALado && (
            <div className="flex w-full gap-2 mb-1">
              {([['lista', 'Lista'], ['agenda', 'Agenda']] as Array<['lista' | 'agenda', string]>).map(([k, r]) => (
                <button key={k} type="button" onClick={() => setModo(k)} className={`wa-chip flex-1 justify-center ${modo === k ? 'wa-chip--on' : ''}`}>{r}</button>
              ))}
            </div>
          )}
          {([['andamento', `Em andamento${abertas ? ` (${abertas})` : ''}`], ['encerradas', 'Encerradas'], ['todas', 'Todas']] as Array<[Filtro, string]>).map(([k, r]) => (
            <button key={k} type="button" onClick={() => setFiltro(k)} className={`wa-chip ${filtro === k ? 'wa-chip--on' : ''}`}>{r}</button>
          ))}
          <label className="wa-busca ml-auto w-full sm:w-[320px] !h-9">
            <MagnifyingGlass size={16} />
            <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Imóvel, código, corretor, proprietário…" aria-label="Buscar visita" />
            {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={14} /></button>}
          </label>
        </div>
      </div>

      <div className="flex-1 min-h-0 flex relative">
      {/* a lista, como sempre foi */}
      <div className={`${!ladoALado && modo === 'agenda' ? 'hidden' : 'flex'} flex-col overflow-y-auto wa-rolagem px-3 py-4 ${ladoALado ? 'w-[clamp(360px,36%,520px)] flex-shrink-0' : 'flex-1 sm:px-6'}`}
           style={ladoALado ? { borderRight: '1px solid var(--wa-divider)' } : undefined}>
        {erro && !visitas.length ? (
          <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-tag-tel)' }}>Não consegui ler as visitas da Nay: {erro}</p>
        ) : carregando && !visitas.length ? (
          <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-text-2)' }}>Carregando as visitas…</p>
        ) : !lista.length ? (
          <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-text-2)' }}>
            {busca ? 'Nenhuma visita com essa busca.' : filtro === 'andamento' ? 'Nenhuma visita em andamento agora.' : 'Nenhuma visita aqui.'}
          </p>
        ) : (
          <div className="w-full max-w-[980px] mx-auto flex flex-col gap-5">
            {grupos.map((g) => (
              <section key={g.dia}>
                <div className="flex justify-center mb-2.5"><span className="wa-data">{g.dia}</span></div>
                <div className="flex flex-col gap-2.5">
                  {g.visitas.map((v) => (
                    <CartaoDaVisita key={v.id} v={v} destacada={selecionada === v.id} aoAbrirConversa={aoAbrirConversa} aoEscolher={escolherNaLista} />
                  ))}
                </div>
              </section>
            ))}
          </div>
        )}
      </div>

      {/* a agenda de verdade, no horário de Manaus */}
      <div className={`${!ladoALado && modo === 'lista' ? 'hidden' : 'flex'} flex-1 min-w-0 flex-col p-2 sm:p-3`}>
        <LegendaDaAgenda />
        <div className="flex-1 min-h-0">
          <AgendaDeVisitas visitas={buscadas} selecionada={selecionada} aoEscolher={escolherNaAgenda}
                           aoArrastar={setArrasto} visivel={ladoALado || modo === 'agenda'} />
        </div>
        {aviso && (
          <div role="status" className="mt-2 px-3 py-2 rounded-lg text-[13.5px] flex items-center gap-2"
               style={{ background: aviso.ok ? 'var(--wa-chip-on-bg)' : 'color-mix(in srgb, var(--wa-tag-tel) 14%, var(--wa-panel))',
                        color: aviso.ok ? 'var(--wa-chip-on-ink)' : 'var(--wa-tag-tel)' }}>
            {aviso.ok ? <CheckCircle size={16} /> : <Warning size={16} />}
            <span className="flex-1">{aviso.texto}</span>
            <button type="button" onClick={() => setAviso(null)} aria-label="Fechar aviso"><X size={14} /></button>
          </div>
        )}
      </div>

      {visitaDoPainel && (
        <PainelDaVisita v={visitaDoPainel} aoFechar={() => setPainel(null)} aoAbrirConversa={aoAbrirConversa} aoMexer={mexer} />
      )}
      </div>

      {arrasto && (
        <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/55 p-4" onClick={cancelarArrasto}>
          <div className="w-full max-w-sm rounded-2xl shadow-2xl p-5" style={{ background: 'var(--wa-menu)', color: 'var(--wa-text)' }}
               onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true" aria-label="Mudar o horário da visita">
            <h3 className="text-[16px] font-semibold mb-1.5" style={{ fontFamily: 'inherit' }}>Mudar o horário da visita?</h3>
            <p className="text-[14px] leading-5">
              {visitaDoArrasto?.imovel || `Visita #${arrasto.visitaId}`}: de {dataHora(arrasto.de)} para{' '}
              <b>{dataHora(arrasto.para)}</b>.
            </p>
            <p className="text-[12.5px] mt-1.5 leading-[17px]" style={{ color: 'var(--wa-text-2)' }}>
              Ninguém recebe mensagem: avise o corretor, o proprietário e o André se precisar.
            </p>
            <div className="flex gap-2 mt-4">
              <button type="button" disabled={gravandoArrasto} onClick={() => void confirmarArrasto()}
                      className="flex-1 inline-flex items-center justify-center gap-1.5 rounded-full h-9 text-[14px] font-medium disabled:opacity-50"
                      style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
                {gravandoArrasto && <CircleNotch size={16} className="animate-spin" />} Mudar o horário
              </button>
              <button type="button" disabled={gravandoArrasto} onClick={cancelarArrasto} className="wa-chip h-9 px-4 rounded-full">Cancelar</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function LegendaDaAgenda() {
  const itens: Array<[string, string]> = [
    ['Em andamento', TOM.andamento], ['Precisa de atenção', TOM.atencao], ['Confirmada', TOM.ok],
    ['Realizada', TOM.fim], ['Cancelada ou expirou', TOM.ruim],
  ]
  return (
    <div className="flex flex-wrap gap-x-3 gap-y-1 px-1 pb-2 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
      {itens.map(([r, c]) => (
        <span key={r} className="inline-flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full" style={{ background: c }} />{r}</span>
      ))}
      <span className="inline-flex items-center gap-1.5"><span className="w-3 h-2.5 rounded-sm border border-dashed" style={{ borderColor: TOM.atencao }} />Horário sugerido</span>
    </div>
  )
}
