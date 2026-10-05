'use client'

/**
 * A AGENDA DAS VISITAS (Pedro, 29/09/2026): "na direita uma agenda real de
 * dias ... com a visita agendada lá no horário já correto".
 *
 * FullCalendar 6 (semana, dia, mês e lista). O horário é SEMPRE o de Manaus
 * (`timeZone: 'America/Manaus'`, pelo plugin do luxon): o computador de quem
 * olha pode estar em Brasília -- o celular do Tel está -- e a visita das 10h
 * não pode aparecer às 11h. Cada visita ocupa 1 hora (a Nay não guarda a
 * duração). Horário sugerido e ainda não aceito aparece tracejado.
 *
 * Arrastar (Pedro, 29/09): a visita que ainda não aconteceu pode ser levada a
 * outro horário. Soltar NÃO grava: a tela pergunta antes (um arrasto sem
 * querer não pode mudar a visita de ninguém), e o "não" devolve ao lugar.
 *
 * O BLOCO (Pedro, 05/10): "o card da visita mais azul para se diferenciar, e que apareça 2 pequenos cards com
 * a foto e o número de quem está naquela visita, ou seja o corretor e o proprietário, posso ir para as conversas
 * deles por ali ao clicar". O bloco é azul (a situação vira a bolinha e o texto da última linha) e leva os dois
 * cartõezinhos; clicar num deles abre a conversa da pessoa, clicar no resto abre o painel da visita.
 *
 * Carregado só no navegador (ver VisitasAgendadas: next/dynamic, ssr false).
 */
import { useEffect, useMemo, useRef } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import dayGridPlugin from '@fullcalendar/daygrid'
import listPlugin from '@fullcalendar/list'
import interactionPlugin from '@fullcalendar/interaction'
import luxonPlugin from '@fullcalendar/luxon3'
import ptBrLocale from '@fullcalendar/core/locales/pt-br'
import type { EventContentArg, EventInput } from '@fullcalendar/core'
import { ESTADO_DA_VISITA, type VisitaNaTela } from '@/lib/tiposNay'

export const FUSO_DE_MANAUS = 'America/Manaus'

/** A cor de cada situação: a mesma do cartão da lista. */
export const COR_DO_TOM: Record<string, string> = {
  andamento: 'var(--wa-tag-visita)',
  atencao: 'var(--wa-tag-prop)',
  ok: 'var(--wa-green)',
  fim: 'var(--wa-text-2)',
  ruim: 'var(--wa-tag-tel)',
}

const UMA_HORA = 60 * 60 * 1000

export interface PessoaDaVisita { papel: 'Corretor' | 'Proprietário'; nome: string | null; telefone: string | null; avatar: string | null; leadId: string | null }

/** "5592991234567" -> "(92) 99123-4567"; curto = "…4567" (a coluna da semana é estreita). */
export function numeroDaPessoa(telefone: string | null, curto = false): string {
  const d = (telefone || '').replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (!d) return 'sem número'
  if (curto) return `…${d.slice(-4)}`
  return d.length >= 10 ? `(${d.slice(0, 2)}) ${d.slice(2, -4)}-${d.slice(-4)}` : d
}

export function pessoasDa(v: VisitaNaTela): PessoaDaVisita[] {
  const lista: PessoaDaVisita[] = [{
    papel: 'Corretor', nome: v.corretorNome || v.conversa?.titulo || null, telefone: v.corretorTelefone || null,
    avatar: v.conversa?.avatar || null, leadId: v.conversa?.leadId || null,
  }]
  if (v.dono || v.proprietarioNome) {
    lista.push({ papel: 'Proprietário', nome: v.proprietarioNome, telefone: v.dono?.telefone || null,
                 avatar: v.dono?.avatar || null, leadId: v.dono?.leadId || null })
  }
  return lista
}

/** Dá para mudar o horário: aberta e ainda não realizada (a Nay decide de novo no banco). */
export function podeMudarHorario(v: VisitaNaTela) {
  return v.aberta && !['realizada', 'encerrada', 'cancelada', 'expirada'].includes(v.estado)
}

function tomDa(v: VisitaNaTela) {
  return (ESTADO_DA_VISITA[v.estado] || { tom: 'fim' as const }).tom
}

function eventosDasVisitas(visitas: VisitaNaTela[], selecionada: number | null): EventInput[] {
  const eventos: EventInput[] = []
  for (const v of visitas) {
    if (!v.quando) continue
    const tom = tomDa(v)
    const titulo = v.codigo ? `${v.codigo} · ${v.imovel || 'Imóvel'}` : (v.imovel || 'Imóvel')
    // com o fuso junto (ISO), a agenda converte para Manaus sem ambiguidade
    eventos.push({
      id: String(v.id),
      title: titulo,
      start: v.quando,
      end: new Date(new Date(v.quando).getTime() + UMA_HORA).toISOString(),
      backgroundColor: 'transparent',
      borderColor: 'transparent',
      startEditable: podeMudarHorario(v),
      durationEditable: false,
      classNames: [
        'agenda-evento',
        `agenda-evento--${tom}`,
        ...(selecionada === v.id ? ['agenda-evento--sel'] : []),
      ],
      extendedProps: { visitaId: v.id, cor: COR_DO_TOM[tom], corretor: v.corretorNome || v.conversa?.titulo || null, estado: ESTADO_DA_VISITA[v.estado]?.rotulo || v.estado, sugerido: false, pessoas: pessoasDa(v) },
    })
    // o horário que alguém sugeriu e ainda não foi aceito
    if (v.aberta && v.quandoSugerido && v.quandoSugerido !== v.quando) {
      eventos.push({
        id: `${v.id}-sugerido`,
        title: `Sugerido: ${titulo}`,
        start: v.quandoSugerido,
        end: new Date(new Date(v.quandoSugerido).getTime() + UMA_HORA).toISOString(),
        backgroundColor: 'transparent',
        borderColor: 'transparent',
        startEditable: false,
        durationEditable: false,
        classNames: ['agenda-evento', 'agenda-evento--sugerido'],
        extendedProps: { visitaId: v.id, cor: 'var(--wa-tag-prop)', corretor: v.corretorNome || null, estado: 'Horário sugerido', sugerido: true, pessoas: [] },
      })
    }
  }
  return eventos
}

/** O cartãozinho da pessoa dentro do bloco: foto (ou a inicial) e o número. Com conversa, o clique abre o chat
    dela (quem ouve é o eventClick da agenda, pelo data-lead). */
function Pessoa({ p, curto }: { p: PessoaDaVisita; curto: boolean }) {
  const dica = `${p.papel}: ${p.nome || 'sem nome'} · ${numeroDaPessoa(p.telefone)}${p.leadId ? ' (abrir a conversa)' : ' (sem conversa no CRM)'}`
  return (
    <span className={`agenda-pessoa ${p.leadId ? '' : 'agenda-pessoa--sem'}`} title={dica} data-lead={p.leadId || undefined}>
      {p.avatar
        ? <img src={p.avatar} alt="" className="agenda-pessoa-foto" />
        : <span className="agenda-pessoa-foto agenda-pessoa-inicial">{p.papel === 'Corretor' ? 'C' : 'P'}</span>}
      <span className="agenda-pessoa-num">{numeroDaPessoa(p.telefone, curto)}</span>
    </span>
  )
}

function ConteudoDoEvento(arg: EventContentArg) {
  const p = arg.event.extendedProps as { cor: string; corretor: string | null; estado: string; sugerido: boolean; pessoas: PessoaDaVisita[] }
  if (arg.view.type.startsWith('list')) {
    return (
      <span className="agenda-lista-linha">
        <span className="font-medium">{arg.event.title}</span>
        {p.corretor && <span className="agenda-lista-sub"> · {p.corretor}</span>}
        <span className="agenda-lista-sub"> · {p.estado}</span>
      </span>
    )
  }
  if (arg.view.type === 'dayGridMonth') {
    return (
      <span className="agenda-mes-linha" title={`${arg.timeText} ${arg.event.title}${p.corretor ? ` · ${p.corretor}` : ''} · ${p.estado}`}>
        <span className="agenda-ponto" style={{ background: p.cor }} />
        <b>{arg.timeText}</b> <span className="truncate">{arg.event.title}</span>
      </span>
    )
  }
  return (
    <div className="agenda-bloco" style={{ ['--cor' as string]: p.cor }}
         title={`${arg.timeText} ${arg.event.title}${p.corretor ? `\nCorretor: ${p.corretor}` : ''}\n${p.estado}`}>
      <span className="agenda-bloco-linha">
        <span className="agenda-bloco-hora">{arg.timeText}</span>
        <span className="agenda-bloco-titulo">{arg.event.title}</span>
      </span>
      {p.pessoas?.length > 0 && (
        <span className="agenda-pessoas">
          {p.pessoas.map((x) => <Pessoa key={x.papel} p={x} curto={arg.view.type !== 'timeGridDay'} />)}
        </span>
      )}
      <span className="agenda-bloco-estado"><span className="agenda-ponto" style={{ background: p.cor }} />{p.estado}</span>
    </div>
  )
}

export interface Arrasto {
  visitaId: number
  /** ISO com o fuso (-04:00) */
  de: string
  para: string
  /** devolve a visita ao lugar (quem cancelou ou a Nay recusou) */
  reverter: () => void
}

export default function AgendaDeVisitas({
  visitas,
  selecionada,
  aoEscolher,
  aoAbrirConversa,
  aoArrastar,
  visivel,
}: {
  visitas: VisitaNaTela[]
  selecionada: number | null
  aoEscolher: (id: number) => void
  /** clicou no cartãozinho do corretor ou do proprietário dentro da visita */
  aoAbrirConversa: (leadId: string) => void
  aoArrastar: (a: Arrasto) => void
  /** muda quando a agenda aparece ou muda de largura: ela recalcula o tamanho */
  visivel: boolean
}) {
  const ref = useRef<FullCalendar>(null)
  const eventos = useMemo(() => eventosDasVisitas(visitas, selecionada), [visitas, selecionada])

  // escolheu na lista: a agenda vai até o dia dela
  useEffect(() => {
    if (!selecionada) return
    const v = visitas.find((x) => x.id === selecionada)
    const api = ref.current?.getApi()
    if (!v?.quando || !api) return
    const quando = new Date(v.quando)
    // o DIA em Manaus (a visita das 21h de Manaus já é o dia seguinte em UTC)
    api.gotoDate(quando.toLocaleDateString('en-CA', { timeZone: FUSO_DE_MANAUS }))
    if (api.view.type.startsWith('timeGrid')) {
      const hora = Number(quando.toLocaleString('en-US', { timeZone: FUSO_DE_MANAUS, hour: '2-digit', hourCycle: 'h23' }))
      api.scrollToTime({ hours: Math.max(0, hora - 1) })
    }
  }, [selecionada, visitas])

  // a agenda escondida (celular, aba "Lista") volta com o tamanho errado sem isto
  useEffect(() => {
    if (!visivel) return
    const id = requestAnimationFrame(() => ref.current?.getApi().updateSize())
    return () => cancelAnimationFrame(id)
  }, [visivel])

  const estreita = typeof window !== 'undefined' && window.innerWidth < 640

  return (
    <div className="agenda-wa h-full min-h-0">
      <FullCalendar
        ref={ref}
        plugins={[timeGridPlugin, dayGridPlugin, listPlugin, interactionPlugin, luxonPlugin]}
        timeZone={FUSO_DE_MANAUS}
        locale={ptBrLocale}
        initialView={estreita ? 'listWeek' : 'timeGridWeek'}
        headerToolbar={estreita
          ? { left: 'prev,next today', center: '', right: 'timeGridDay,listWeek' }
          : { left: 'prev,next today', center: 'title', right: 'dayGridMonth,timeGridWeek,timeGridDay,listWeek' }}
        buttonText={{ today: 'Hoje', month: 'Mês', week: 'Semana', day: 'Dia', list: 'Lista' }}
        height="100%"
        events={eventos}
        eventContent={ConteudoDoEvento}
        eventClick={(info) => {
          info.jsEvent.preventDefault()
          const lead = (info.jsEvent.target as HTMLElement | null)?.closest?.('[data-lead]')?.getAttribute('data-lead')
          if (lead) { aoAbrirConversa(lead); return }
          const id = Number(info.event.extendedProps.visitaId)
          if (id) aoEscolher(id)
        }}
        eventDrop={(info) => {
          const id = Number(info.event.extendedProps.visitaId)
          if (!id || !info.event.startStr) { info.revert(); return }
          aoArrastar({ visitaId: id, de: info.oldEvent.startStr, para: info.event.startStr, reverter: info.revert })
        }}
        eventDurationEditable={false}
        snapDuration="00:15:00"
        allDaySlot={false}
        nowIndicator
        slotMinTime="06:00:00"
        slotMaxTime="22:00:00"
        scrollTime="08:00:00"
        slotDuration="00:30:00"
        slotLabelFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
        eventTimeFormat={{ hour: '2-digit', minute: '2-digit', hour12: false }}
        displayEventEnd={false}
        firstDay={0}
        dayMaxEvents={4}
        expandRows
        stickyHeaderDates
        noEventsContent="Nenhuma visita neste período"
      />
    </div>
  )
}
