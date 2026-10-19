'use client'

/**
 * AGENDAR FOLLOW-UP no card do contato (Pedro, 30/09/2026): "eu coloco a mensagem,
 * quando quero que envie -- amanhã, uma semana, ou data específica (um ícone de
 * calendário) -- e a hora, e clico em salvar". Quem envia na hora é o servidor
 * (/api/cron/followups), pela linha desta conversa.
 *
 * A HORA É A DE MANAUS (Pedro, 03/10/2026: "pode colocar os fusos tudo de Manaus?").
 * O dia e a hora digitados eram lidos no relógio do computador: com a máquina em
 * Brasília, "09:00" saía às 08:00 de Manaus. Ver src/lib/fusoDeManaus.ts.
 *
 * 19/10/2026 (Pedro): "no de enviar follow-up quero a opção Hoje também, e uma opção editar o follow-up já agendado,
 * e quero que se a Nay já tiver agendado um follow-up para aquele lead apareça ali como criado pela Nay também".
 *   - Hoje: o dia de hoje; se a hora escolhida já passou, vai para a próxima hora cheia.
 *   - Editar (lápis): o agendado volta para o formulário; salvar troca a mensagem e a hora (PATCH).
 *   - Nay (`mostrarNay`, só na Parceria): o follow-up dela vem da regra do nai_followup_rodar (414), previsto e feitos.
 */
import { useCallback, useEffect, useState } from 'react'
import { CalendarBlank, CircleNotch, Clock, PencilSimple, Robot, X } from '@phosphor-icons/react'
import { dataHoraEmManaus, diaEmManausMais, horaEmManaus, instanteEmManaus } from '@/lib/fusoDeManaus'

interface Followup { id: string; mensagem: string; enviar_em: string; estado: string; criado_por_nome: string | null; erro: string | null }
interface FollowupDaNay { estado: 'previsto' | 'enviado' | 'pulado'; quando: string; mensagem: string | null; motivo: string | null; codigos: number[] | null }
type Atalho = 'hoje' | 'amanha' | 'semana' | 'data'

/** yyyy-mm-dd do dia de hoje + n, no calendário de Manaus */
const diaMais = (n: number) => diaEmManausMais(n)
/** "04/10 às 09:00", em Manaus */
const quandoCurto = (iso: string) => dataHoraEmManaus(iso, ' às ')
/** a próxima hora cheia de Manaus, "15:00" (o Hoje com uma hora que já passou) */
function proximaHoraCheia(): string {
  const h = Number(horaEmManaus(new Date()).slice(0, 2)) + 1
  return `${String(Math.min(h, 23)).padStart(2, '0')}:00`
}

export default function AgendarFollowup({ leadId, semTitulo = false, mostrarNay = false }: {
  leadId: string
  /** o card em volta já tem o título (Parceria, 19/10) */
  semTitulo?: boolean
  /** mostra o follow-up da Nay (só a Parceria tem a Nay que faz follow-up) */
  mostrarNay?: boolean
}) {
  const [mensagem, setMensagem] = useState('')
  const [atalho, setAtalho] = useState<Atalho>('amanha')
  const [dia, setDia] = useState(diaMais(1))
  const [hora, setHora] = useState('09:00')
  const [salvando, setSalvando] = useState(false)
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)
  const [lista, setLista] = useState<Followup[]>([])
  const [daNay, setDaNay] = useState<FollowupDaNay[]>([])
  const [editando, setEditando] = useState<string | null>(null)

  const carregar = useCallback(async () => {
    const r = await fetch(`/api/leads/${leadId}/followups`).catch(() => null)
    const j = r && r.ok ? await r.json().catch(() => ({})) : {}
    setLista(Array.isArray(j.followups) ? j.followups : [])
    setDaNay(Array.isArray(j.nay) ? j.nay : [])
  }, [leadId])
  const limpar = () => { setMensagem(''); setAtalho('amanha'); setDia(diaMais(1)); setHora('09:00'); setEditando(null) }
  useEffect(() => { limpar(); setAviso(null); void carregar() }, [leadId, carregar]) // eslint-disable-line react-hooks/exhaustive-deps

  const escolher = (a: Atalho) => {
    setAtalho(a)
    if (a === 'hoje') {
      setDia(diaMais(0))
      // 09:00 de hoje já passou na maior parte do dia: vai para a próxima hora cheia
      if (instanteEmManaus(diaMais(0), hora).getTime() < Date.now() + 60_000) setHora(proximaHoraCheia())
    }
    if (a === 'amanha') setDia(diaMais(1))
    if (a === 'semana') setDia(diaMais(7))
  }

  const editar = (f: Followup) => {
    const d = new Date(f.enviar_em)
    const diaDele = d.toLocaleDateString('en-CA', { timeZone: 'America/Manaus' })
    setEditando(f.id)
    setMensagem(f.mensagem)
    setDia(diaDele)
    setHora(horaEmManaus(d))
    setAtalho(diaDele === diaMais(0) ? 'hoje' : diaDele === diaMais(1) ? 'amanha' : diaDele === diaMais(7) ? 'semana' : 'data')
    setAviso(null)
  }

  const salvar = async () => {
    if (!mensagem.trim()) { setAviso({ ok: false, texto: 'Escreva a mensagem.' }); return }
    const quando = instanteEmManaus(dia, hora)
    if (Number.isNaN(quando.getTime())) { setAviso({ ok: false, texto: 'Escolha o dia e a hora.' }); return }
    if (quando.getTime() < Date.now() + 60_000) { setAviso({ ok: false, texto: 'Esse horário já passou. Escolha um mais tarde.' }); return }
    setSalvando(true); setAviso(null)
    try {
      const r = await fetch(`/api/leads/${leadId}/followups`, {
        method: editando ? 'PATCH' : 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...(editando ? { fid: editando } : {}), mensagem: mensagem.trim(), enviar_em: quando.toISOString() }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui salvar.')
      setAviso({ ok: true, texto: `${editando ? 'Alterado' : 'Agendado'} para ${quandoCurto(quando.toISOString())}.` })
      limpar()
      void carregar()
    } catch (e: any) {
      setAviso({ ok: false, texto: e?.message || 'Não consegui salvar.' })
    } finally { setSalvando(false) }
  }

  const cancelar = async (fid: string) => {
    await fetch(`/api/leads/${leadId}/followups?fid=${fid}`, { method: 'DELETE' }).catch(() => null)
    if (editando === fid) limpar()
    void carregar()
  }

  const chip = (a: Atalho, rotulo: React.ReactNode) => (
    <button type="button" onClick={() => escolher(a)} aria-pressed={atalho === a}
            className="inline-flex items-center gap-1 h-7 px-2.5 rounded-full text-[12.5px] font-medium"
            style={atalho === a
              ? { background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }
              : { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' }}>
      {rotulo}
    </button>
  )
  const campo = { background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }
  const pendentes = lista.filter((f) => f.estado === 'agendado' || f.estado === 'enviando')
  const ultimos = lista.filter((f) => f.estado === 'enviado' || f.estado === 'falhou').slice(0, 3)
  const naySeguinte = mostrarNay ? daNay.filter((n) => n.estado === 'previsto') : []
  const nayFeitos = mostrarNay ? daNay.filter((n) => n.estado !== 'previsto').slice(0, 2) : []
  const corDaNay = '#7c3aed'

  return (
    <div className={`w-full text-left ${semTitulo ? '' : 'mt-4'}`}>
      {!semTitulo && (
        <label htmlFor={`fu-${leadId}`} className="text-[13px] block mb-1" style={{ color: 'var(--wa-text-2)' }}>Agendar follow-up</label>
      )}
      {editando && (
        <p className="text-[12.5px] mb-1.5 flex items-center gap-1.5" style={{ color: 'var(--wa-tag-prop)' }}>
          <PencilSimple size={13} /> Editando um follow-up agendado
          <button type="button" onClick={() => { limpar(); setAviso(null) }} className="underline ml-1">cancelar edição</button>
        </p>
      )}
      <textarea id={`fu-${leadId}`} value={mensagem} rows={3} maxLength={4000}
                onChange={(e) => setMensagem(e.target.value)}
                placeholder="A mensagem que vai ser enviada para esta pessoa no dia e hora marcados"
                className="w-full rounded-lg px-3 py-2 text-[14px] leading-5 resize-y min-h-[72px]" style={campo} />
      <div className="flex flex-wrap items-center gap-1.5 mt-2">
        {chip('hoje', 'Hoje')}
        {chip('amanha', 'Amanhã')}
        {chip('semana', 'Uma semana')}
        {chip('data', <><CalendarBlank size={14} /> Data</>)}
        {atalho === 'data' && (
          <input type="date" value={dia} min={diaMais(0)} onChange={(e) => setDia(e.target.value)}
                 aria-label="Dia do envio" className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
        )}
        <span className="inline-flex items-center gap-1 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }} title="Horário de Manaus">
          <Clock size={14} />
          <input type="time" value={hora} onChange={(e) => setHora(e.target.value)}
                 aria-label="Hora do envio (horário de Manaus)" className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
          <span className="text-[11.5px]">Manaus</span>
        </span>
      </div>
      <button type="button" onClick={() => void salvar()} disabled={salvando || !mensagem.trim()}
              className="mt-2 inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
              style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
        {salvando ? <CircleNotch size={14} className="animate-spin" /> : <CalendarBlank size={14} weight="fill" />}
        {editando ? 'Salvar alteração' : 'Salvar agendamento'}
      </button>
      {aviso && <p className="text-[12.5px] mt-1.5 leading-4" style={{ color: aviso.ok ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>{aviso.texto}</p>}

      {(pendentes.length > 0 || ultimos.length > 0 || naySeguinte.length > 0 || nayFeitos.length > 0) && (
        <ul className="mt-3 space-y-1.5">
          {/* o da Nay, previsto: ela confere na hora e pode pular */}
          {naySeguinte.map((n, i) => (
            <li key={`nay-prev-${i}`} className="rounded-lg px-2.5 py-1.5 text-[12.5px]"
                style={{ ...campo, borderColor: `color-mix(in srgb, ${corDaNay} 45%, transparent)` }}
                title={n.motivo || ''}>
              <span className="inline-flex items-center gap-1 font-semibold" style={{ color: corDaNay }}>
                <Robot size={13} weight="fill" /> Criado pela Nay
              </span>
              <span className="block"><b>{quandoCurto(n.quando)}</b> · previsto{n.codigos?.length ? ` · imóve${n.codigos.length > 1 ? 'is' : 'l'} ${n.codigos.join(', ')}` : ''}</span>
              {n.mensagem && <span className="block truncate" style={{ color: 'var(--wa-text-2)' }}>{n.mensagem.split('\n')[0]}</span>}
              <span className="block text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>Ela confere na hora: pula se ele já conversou no dia, recusou, tem visita aberta ou está com o Tel.</span>
            </li>
          ))}
          {pendentes.map((f) => (
            <li key={f.id} className="flex items-start gap-2 rounded-lg px-2.5 py-1.5 text-[12.5px]"
                style={editando === f.id ? { ...campo, borderColor: 'var(--wa-tag-prop)' } : campo}>
              <span className="flex-1 min-w-0">
                <b>{quandoCurto(f.enviar_em)}</b>{f.criado_por_nome ? ` · ${f.criado_por_nome}` : ''}
                <span className="block truncate" style={{ color: 'var(--wa-text-2)' }}>{f.mensagem}</span>
              </span>
              {f.estado === 'agendado' && (
                <span className="flex items-center gap-1 flex-shrink-0">
                  <button type="button" onClick={() => editar(f)} title="Editar a mensagem e a hora" aria-label="Editar este agendamento"><PencilSimple size={14} /></button>
                  <button type="button" onClick={() => void cancelar(f.id)} title="Cancelar este agendamento" aria-label="Cancelar este agendamento"><X size={14} /></button>
                </span>
              )}
            </li>
          ))}
          {ultimos.map((f) => (
            <li key={f.id} className="rounded-lg px-2.5 py-1.5 text-[12.5px]" style={{ ...campo, opacity: 0.75 }}>
              {f.estado === 'enviado' ? 'Enviado' : 'Não saiu'} · {quandoCurto(f.enviar_em)}
              {f.estado === 'falhou' && f.erro ? <span className="block" style={{ color: 'var(--wa-tag-tel)' }}>{f.erro}</span> : null}
              <span className="block truncate" style={{ color: 'var(--wa-text-2)' }}>{f.mensagem}</span>
            </li>
          ))}
          {/* o que a Nay já fez (enviou ou pulou, com o motivo) */}
          {nayFeitos.map((n, i) => (
            <li key={`nay-feito-${i}`} className="rounded-lg px-2.5 py-1.5 text-[12.5px]" style={{ ...campo, opacity: 0.75 }}>
              <span className="inline-flex items-center gap-1" style={{ color: corDaNay }}><Robot size={12} weight="fill" /> Nay</span>
              {' · '}{n.estado === 'enviado' ? 'Enviado' : 'Pulou'} · {quandoCurto(n.quando)}
              {n.estado === 'pulado' && n.motivo ? <span className="block" style={{ color: 'var(--wa-text-2)' }}>{n.motivo}</span> : null}
              {n.estado === 'enviado' && n.mensagem ? <span className="block truncate" style={{ color: 'var(--wa-text-2)' }}>{n.mensagem.split('\n')[0]}</span> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
