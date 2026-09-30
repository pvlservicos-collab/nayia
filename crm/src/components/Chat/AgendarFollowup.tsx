'use client'

/**
 * AGENDAR FOLLOW-UP no card do contato (Pedro, 30/09/2026): "eu coloco a mensagem,
 * quando quero que envie -- amanhã, uma semana, ou data específica (um ícone de
 * calendário) -- e a hora, e clico em salvar". Quem envia na hora é o servidor
 * (/api/cron/followups), pela linha desta conversa.
 */
import { useCallback, useEffect, useState } from 'react'
import { CalendarBlank, CircleNotch, Clock, X } from '@phosphor-icons/react'

interface Followup { id: string; mensagem: string; enviar_em: string; estado: string; criado_por_nome: string | null; erro: string | null }

const doisDigitos = (n: number) => String(n).padStart(2, '0')
/** yyyy-mm-dd do dia de hoje + n, no relógio de quem está usando */
function diaMais(n: number): string {
  const d = new Date(); d.setDate(d.getDate() + n)
  return `${d.getFullYear()}-${doisDigitos(d.getMonth() + 1)}-${doisDigitos(d.getDate())}`
}
function quandoCurto(iso: string): string {
  const d = new Date(iso)
  return `${doisDigitos(d.getDate())}/${doisDigitos(d.getMonth() + 1)} às ${doisDigitos(d.getHours())}:${doisDigitos(d.getMinutes())}`
}

export default function AgendarFollowup({ leadId }: { leadId: string }) {
  const [mensagem, setMensagem] = useState('')
  const [atalho, setAtalho] = useState<'amanha' | 'semana' | 'data'>('amanha')
  const [dia, setDia] = useState(diaMais(1))
  const [hora, setHora] = useState('09:00')
  const [salvando, setSalvando] = useState(false)
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)
  const [lista, setLista] = useState<Followup[]>([])

  const carregar = useCallback(async () => {
    const r = await fetch(`/api/leads/${leadId}/followups`).catch(() => null)
    const j = r && r.ok ? await r.json().catch(() => ({})) : {}
    setLista(Array.isArray(j.followups) ? j.followups : [])
  }, [leadId])
  useEffect(() => { setMensagem(''); setAviso(null); setAtalho('amanha'); setDia(diaMais(1)); void carregar() }, [leadId, carregar])

  const escolher = (a: 'amanha' | 'semana' | 'data') => {
    setAtalho(a)
    if (a === 'amanha') setDia(diaMais(1))
    if (a === 'semana') setDia(diaMais(7))
  }

  const salvar = async () => {
    if (!mensagem.trim()) { setAviso({ ok: false, texto: 'Escreva a mensagem.' }); return }
    const quando = new Date(`${dia}T${hora}:00`)
    if (Number.isNaN(quando.getTime())) { setAviso({ ok: false, texto: 'Escolha o dia e a hora.' }); return }
    setSalvando(true); setAviso(null)
    try {
      const r = await fetch(`/api/leads/${leadId}/followups`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ mensagem: mensagem.trim(), enviar_em: quando.toISOString() }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || j?.message || 'Não consegui salvar.')
      setAviso({ ok: true, texto: `Agendado para ${quandoCurto(quando.toISOString())}.` })
      setMensagem('')
      void carregar()
    } catch (e: any) {
      setAviso({ ok: false, texto: e?.message || 'Não consegui salvar.' })
    } finally { setSalvando(false) }
  }

  const cancelar = async (fid: string) => {
    await fetch(`/api/leads/${leadId}/followups?fid=${fid}`, { method: 'DELETE' }).catch(() => null)
    void carregar()
  }

  const chip = (a: 'amanha' | 'semana' | 'data', rotulo: React.ReactNode) => (
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

  return (
    <div className="w-full mt-4 text-left">
      <label htmlFor={`fu-${leadId}`} className="text-[13px] block mb-1" style={{ color: 'var(--wa-text-2)' }}>Agendar follow-up</label>
      <textarea id={`fu-${leadId}`} value={mensagem} rows={3} maxLength={4000}
                onChange={(e) => setMensagem(e.target.value)}
                placeholder="A mensagem que vai ser enviada para esta pessoa no dia e hora marcados"
                className="w-full rounded-lg px-3 py-2 text-[14px] leading-5 resize-y min-h-[72px]" style={campo} />
      <div className="flex flex-wrap items-center gap-1.5 mt-2">
        {chip('amanha', 'Amanhã')}
        {chip('semana', 'Uma semana')}
        {chip('data', <><CalendarBlank size={14} /> Data</>)}
        {atalho === 'data' && (
          <input type="date" value={dia} min={diaMais(0)} onChange={(e) => setDia(e.target.value)}
                 aria-label="Dia do envio" className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
        )}
        <span className="inline-flex items-center gap-1 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          <Clock size={14} />
          <input type="time" value={hora} onChange={(e) => setHora(e.target.value)}
                 aria-label="Hora do envio" className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
        </span>
      </div>
      <button type="button" onClick={() => void salvar()} disabled={salvando || !mensagem.trim()}
              className="mt-2 inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
              style={{ background: 'var(--wa-green)', color: 'var(--wa-green-ink)' }}>
        {salvando ? <CircleNotch size={14} className="animate-spin" /> : <CalendarBlank size={14} weight="fill" />} Salvar agendamento
      </button>
      {aviso && <p className="text-[12.5px] mt-1.5 leading-4" style={{ color: aviso.ok ? 'var(--wa-green)' : 'var(--wa-tag-tel)' }}>{aviso.texto}</p>}
      {(pendentes.length > 0 || ultimos.length > 0) && (
        <ul className="mt-2 space-y-1.5">
          {pendentes.map((f) => (
            <li key={f.id} className="flex items-start gap-2 rounded-lg px-2.5 py-1.5 text-[12.5px]" style={campo}>
              <span className="flex-1 min-w-0">
                <b>{quandoCurto(f.enviar_em)}</b>{f.criado_por_nome ? ` · ${f.criado_por_nome}` : ''}
                <span className="block truncate" style={{ color: 'var(--wa-text-2)' }}>{f.mensagem}</span>
              </span>
              {f.estado === 'agendado' && (
                <button type="button" onClick={() => void cancelar(f.id)} title="Cancelar este agendamento" aria-label="Cancelar este agendamento"><X size={14} /></button>
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
        </ul>
      )}
    </div>
  )
}
