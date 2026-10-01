'use client'

/**
 * AGENDAR VISITA À MÃO (Pedro, 01/10/2026): "cria uma função no card dos
 * proprietários, agendar visita. Eu vou agendar manualmente: vou pôr o corretor,
 * a duração e o dia, e posso adicionar um lembrete ali mesmo, igual esse
 * lembrete de mensagem, mas essa função quero em azul para diferenciar. E lá em
 * agenda também um + que vai agendar pela agenda também... por padrão o lembrete
 * já vem configurado para 1 hora antes."
 *
 * O mesmo formulário nos dois lugares: aberto dentro do card do proprietário
 * (o imóvel já é um dos dele, e o lembrete do dono vai para esta conversa) e
 * num popup pelo + da agenda (aí o código do imóvel é digitado).
 *
 * É AZUL de propósito: o verde do card é follow-up (uma mensagem), o azul é
 * visita (entra na agenda).
 *
 * A visita nasce da equipe (migração 250): a Nay não manda nada sozinha. Quem
 * avisa é o lembrete marcado aqui -- uma mensagem agendada na conversa do
 * corretor e/ou do proprietário, que segue a visita se ela mudar de hora.
 */
import { useEffect, useMemo, useState } from 'react'
import { CalendarPlus, CircleNotch, Clock, CalendarBlank, BellRinging, X } from '@phosphor-icons/react'

const AZUL = '#2563eb'
const AZUL_SUAVE = 'color-mix(in srgb, #2563eb 14%, transparent)'

interface Corretor { leadId: string; nome: string; fim: string }

const dois = (n: number) => String(n).padStart(2, '0')
function diaMais(n: number): string {
  const d = new Date(); d.setDate(d.getDate() + n)
  return `${d.getFullYear()}-${dois(d.getMonth() + 1)}-${dois(d.getDate())}`
}
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

const DURACOES: Array<[number, string]> = [[30, '30 min'], [60, '1 h'], [90, '1h30'], [120, '2 h']]
/* por padrão, 1 hora antes (Pedro, 01/10) */
const ANTECEDENCIAS: Array<[number, string]> = [[30, '30 min antes'], [60, '1 hora antes'], [120, '2 horas antes'], [1440, '1 dia antes']]

export default function AgendarVisita({ imoveis, proprietarioLeadId, codigoInicial, quandoInicial, aoAgendar, aoCancelar }: {
  /** os imóveis do dono deste card (aí o código é escolhido, não digitado) */
  imoveis?: string[]
  /** a conversa do proprietário: o lembrete dele sai por ela */
  proprietarioLeadId?: string
  codigoInicial?: string
  /** dia/hora já escolhidos (o + da agenda pode abrir num horário) */
  quandoInicial?: Date
  aoAgendar?: (visita: number) => void
  aoCancelar?: () => void
}) {
  const [corretores, setCorretores] = useState<Corretor[]>([])
  const [codigo, setCodigo] = useState(codigoInicial || imoveis?.[0] || '')
  const [buscaCorretor, setBuscaCorretor] = useState('')
  const [corretor, setCorretor] = useState<Corretor | null>(null)
  const [atalho, setAtalho] = useState<'hoje' | 'amanha' | 'data'>(quandoInicial ? 'data' : 'amanha')
  const [dia, setDia] = useState(() => quandoInicial
    ? `${quandoInicial.getFullYear()}-${dois(quandoInicial.getMonth() + 1)}-${dois(quandoInicial.getDate())}` : diaMais(1))
  const [hora, setHora] = useState(() => quandoInicial ? `${dois(quandoInicial.getHours())}:${dois(quandoInicial.getMinutes())}` : '10:00')
  const [duracao, setDuracao] = useState(60)
  const [lembrar, setLembrar] = useState(true)
  const [antes, setAntes] = useState(60)
  const [paraCorretor, setParaCorretor] = useState(true)
  const [paraDono, setParaDono] = useState(true)
  const [mensagem, setMensagem] = useState('')
  const [salvando, setSalvando] = useState(false)
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)

  useEffect(() => {
    let vivo = true
    fetch('/api/parceria/visitas/opcoes')
      .then((r) => (r.ok ? r.json() : { corretores: [] }))
      .then((j) => { if (vivo) setCorretores(Array.isArray(j.corretores) ? j.corretores : []) })
      .catch(() => {})
    return () => { vivo = false }
  }, [])

  const digitos = buscaCorretor.replace(/\D/g, '')
  const sugestoes = useMemo(() => {
    const q = sem(buscaCorretor.trim())
    if (!q || corretor) return []
    return corretores.filter((c) => sem(c.nome).includes(q) || (digitos.length >= 3 && c.fim.includes(digitos.slice(-4)))).slice(0, 6)
  }, [corretores, buscaCorretor, corretor, digitos])
  /* não está na lista: vale o número digitado (com DDD) */
  const numeroDigitado = !corretor && digitos.length >= 10 ? digitos : null

  const escolher = (a: 'hoje' | 'amanha' | 'data') => {
    setAtalho(a)
    if (a === 'hoje') setDia(diaMais(0))
    if (a === 'amanha') setDia(diaMais(1))
  }

  const doisDestinos = lembrar && paraCorretor && paraDono

  async function agendar() {
    if (salvando) return
    if (!/^\d{1,6}$/.test(codigo.trim())) { setAviso({ ok: false, texto: 'Diga o código do imóvel.' }); return }
    if (!corretor && !numeroDigitado) { setAviso({ ok: false, texto: 'Escolha o corretor na lista ou digite o número dele com DDD.' }); return }
    const quando = new Date(`${dia}T${hora}:00`)
    if (Number.isNaN(quando.getTime())) { setAviso({ ok: false, texto: 'Escolha o dia e a hora.' }); return }
    setSalvando(true); setAviso(null)
    try {
      const r = await fetch('/api/parceria/visitas', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          codigo: Number(codigo.trim()),
          corretor: corretor ? { leadId: corretor.leadId, nome: corretor.nome } : { telefone: numeroDigitado },
          quando: quando.toISOString(),
          duracaoMin: duracao,
          lembrete: lembrar && (paraCorretor || paraDono)
            ? { minutosAntes: antes, corretor: paraCorretor, proprietario: paraDono, mensagem: mensagem.trim() || undefined }
            : undefined,
          proprietarioLeadId,
        }),
      })
      const j = await r.json().catch(() => ({} as any))
      if (!r.ok || !j?.ok) throw new Error(j?.mensagem || j?.error || 'Não consegui agendar.')
      const partes = [String(j.mensagem || 'Visita agendada.')]
      if (Array.isArray(j.lembretes) && j.lembretes.length) {
        partes.push(`Lembrete para ${j.lembretes.map((l: any) => (l.para === 'corretor' ? 'o corretor' : 'o proprietário')).join(' e ')}.`)
      }
      if (Array.isArray(j.avisos)) partes.push(...j.avisos)
      setAviso({ ok: true, texto: partes.join(' ') })
      setMensagem('')
      aoAgendar?.(Number(j.visita))
    } catch (e: any) {
      setAviso({ ok: false, texto: e?.message || 'Não consegui agendar.' })
    } finally { setSalvando(false) }
  }

  const campo = { background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }
  const chip = (ligado: boolean) => (ligado
    ? { background: AZUL, color: '#fff' }
    : { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' })
  const classeChip = 'inline-flex items-center gap-1 h-7 px-2.5 rounded-full text-[12.5px] font-medium'
  const rotulo = 'text-[12px] block mb-1'

  return (
    <div className="w-full text-left rounded-xl p-3" style={{ border: `1px solid ${AZUL}`, background: AZUL_SUAVE }}>
      <div className="flex items-center gap-1.5 mb-2">
        <CalendarPlus size={17} weight="fill" style={{ color: AZUL }} />
        <b className="text-[14px]" style={{ color: AZUL }}>Agendar visita</b>
        {aoCancelar && (
          <button type="button" onClick={aoCancelar} className="ml-auto wa-icone-btn !w-7 !h-7" aria-label="Fechar"><X size={15} /></button>
        )}
      </div>

      {/* o imóvel */}
      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Imóvel</label>
      {imoveis && imoveis.length > 0 ? (
        <div className="flex flex-wrap gap-1.5 mb-2.5">
          {imoveis.map((c) => (
            <button key={c} type="button" onClick={() => setCodigo(c)} aria-pressed={codigo === c} className={classeChip} style={chip(codigo === c)}>#{c}</button>
          ))}
        </div>
      ) : (
        <input value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, '').slice(0, 6))} inputMode="numeric"
               placeholder="código do imóvel" aria-label="Código do imóvel"
               className="w-full h-8 rounded-lg px-2.5 text-[13.5px] mb-2.5" style={campo} />
      )}

      {/* o corretor */}
      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Corretor</label>
      {corretor ? (
        <div className="flex items-center gap-2 h-8 rounded-lg px-2.5 text-[13.5px] mb-2.5" style={campo}>
          <span className="flex-1 truncate">{corretor.nome} <span style={{ color: 'var(--wa-text-2)' }}>· final {corretor.fim}</span></span>
          <button type="button" onClick={() => { setCorretor(null); setBuscaCorretor('') }} aria-label="Trocar o corretor"><X size={14} /></button>
        </div>
      ) : (
        <div className="mb-2.5">
          <input value={buscaCorretor} onChange={(e) => setBuscaCorretor(e.target.value)}
                 placeholder="nome do corretor, ou o número com DDD" aria-label="Corretor"
                 className="w-full h-8 rounded-lg px-2.5 text-[13.5px]" style={campo} />
          {sugestoes.length > 0 && (
            <ul className="mt-1 rounded-lg overflow-hidden" style={campo}>
              {sugestoes.map((c) => (
                <li key={c.leadId}>
                  <button type="button" onClick={() => setCorretor(c)}
                          className="w-full text-left px-2.5 py-1.5 text-[13px] hover:opacity-80" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
                    {c.nome} <span style={{ color: 'var(--wa-text-2)' }}>· final {c.fim}</span>
                  </button>
                </li>
              ))}
            </ul>
          )}
          {numeroDigitado && (
            <p className="text-[11.5px] mt-1" style={{ color: 'var(--wa-text-2)' }}>Não está na lista: vale o número digitado.</p>
          )}
        </div>
      )}

      {/* o dia, a hora e a duração */}
      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Dia e hora</label>
      <div className="flex flex-wrap items-center gap-1.5 mb-2.5">
        <button type="button" onClick={() => escolher('hoje')} aria-pressed={atalho === 'hoje'} className={classeChip} style={chip(atalho === 'hoje')}>Hoje</button>
        <button type="button" onClick={() => escolher('amanha')} aria-pressed={atalho === 'amanha'} className={classeChip} style={chip(atalho === 'amanha')}>Amanhã</button>
        <button type="button" onClick={() => escolher('data')} aria-pressed={atalho === 'data'} className={classeChip} style={chip(atalho === 'data')}><CalendarBlank size={14} /> Data</button>
        {atalho === 'data' && (
          <input type="date" value={dia} min={diaMais(0)} onChange={(e) => setDia(e.target.value)} aria-label="Dia da visita"
                 className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
        )}
        <span className="inline-flex items-center gap-1 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          <Clock size={14} />
          <input type="time" value={hora} onChange={(e) => setHora(e.target.value)} aria-label="Hora da visita"
                 className="h-7 rounded-lg px-2 text-[12.5px]" style={campo} />
        </span>
      </div>

      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Duração</label>
      <div className="flex flex-wrap gap-1.5 mb-2.5">
        {DURACOES.map(([m, r]) => (
          <button key={m} type="button" onClick={() => setDuracao(m)} aria-pressed={duracao === m} className={classeChip} style={chip(duracao === m)}>{r}</button>
        ))}
      </div>

      {/* o lembrete: ligado, 1 hora antes */}
      <label className="flex items-center gap-1.5 text-[13px] mb-1.5 cursor-pointer" style={{ color: 'var(--wa-text)' }}>
        <input type="checkbox" checked={lembrar} onChange={(e) => setLembrar(e.target.checked)} style={{ accentColor: AZUL }} />
        <BellRinging size={15} style={{ color: AZUL }} /> Lembrete da visita
      </label>
      {lembrar && (
        <div className="pl-1 mb-2.5">
          <div className="flex flex-wrap items-center gap-1.5">
            <select value={antes} onChange={(e) => setAntes(Number(e.target.value))} aria-label="Quanto antes da visita"
                    className="h-7 rounded-lg px-2 text-[12.5px]" style={campo}>
              {ANTECEDENCIAS.map(([m, r]) => <option key={m} value={m}>{r}</option>)}
            </select>
            <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>para</span>
            <button type="button" onClick={() => setParaCorretor((v) => !v)} aria-pressed={paraCorretor} className={classeChip} style={chip(paraCorretor)}>Corretor</button>
            <button type="button" onClick={() => setParaDono((v) => !v)} aria-pressed={paraDono} className={classeChip} style={chip(paraDono)}>Proprietário</button>
          </div>
          <textarea value={mensagem} onChange={(e) => setMensagem(e.target.value)} rows={2} maxLength={4000} disabled={doisDestinos}
                    placeholder={doisDestinos
                      ? 'Com os dois marcados, cada um recebe o lembrete de sempre: "Oi, Fulano! Passando para lembrar da visita hoje às 15:00…"'
                      : 'Deixe vazio para o lembrete de sempre, ou escreva o seu'}
                    className="w-full mt-1.5 rounded-lg px-2.5 py-1.5 text-[13px] leading-5 resize-y disabled:opacity-70" style={campo} />
        </div>
      )}

      <button type="button" onClick={() => void agendar()} disabled={salvando}
              className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
              style={{ background: AZUL, color: '#fff' }}>
        {salvando ? <CircleNotch size={14} className="animate-spin" /> : <CalendarPlus size={14} weight="fill" />} Agendar visita
      </button>
      {aviso && <p className="text-[12.5px] mt-1.5 leading-4" style={{ color: aviso.ok ? AZUL : 'var(--wa-tag-tel)' }}>{aviso.texto}</p>}
      <p className="text-[11px] mt-1.5 leading-4" style={{ color: 'var(--wa-text-2)' }}>
        Entra na agenda como visita da equipe: a Nay não manda nada sozinha, e o corretor fica na etapa Visitas até ela acabar.
      </p>
    </div>
  )
}
