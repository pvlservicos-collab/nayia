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
 *
 * O LEMBRETE VEM DESMARCADO E COM A MENSAGEM PRONTA (Pedro, 01/10/2026: "esse
 * lembrete quero desmarcado e já com uma mensagem padrão pronta lá na janela
 * ... desmarca corretor e proprietário"). Corretor e Proprietário começam
 * apagados: quem agenda escolhe para quem vai, e sem ninguém marcado a visita
 * entra na agenda sem lembrete. A mensagem padrão já está escrita na caixa, com
 * as marcas {nome}, {quando} e {imóvel}, que a rota troca para cada pessoa --
 * ver src/lib/lembreteDaVisitaTexto.ts.
 *
 * ESTÁ NO CARD DE TODA CONVERSA da Parceria, não só no do proprietário (mesmo
 * pedido: "quero que isso fique lá no card da conversa"). No card de um
 * corretor ele já vem escolhido (`corretorInicial`) e o código é digitado.
 *
 * O IMÓVEL PELO NOME (Pedro, 03/10/2026): "coloca por nome de condomínio também,
 * ao aparecer a gente ver as opções, porque lembrar do código e ir lá ver no site
 * nos toma tempo". O campo do imóvel é o EscolherImovelDaVisita: código ou nome,
 * com a lista para escolher. No card do dono, cada imóvel dele mostra o nome.
 *
 * A HORA É A DE MANAUS (mesmo pedido: "está com o horário de São Paulo na hora de
 * agendar... pode colocar os fusos tudo de Manaus?"). O dia e a hora digitados são
 * lidos como hora de Manaus, e "hoje"/"amanhã" são os de Manaus, seja qual for o
 * relógio do computador -- ver src/lib/fusoDeManaus.ts.
 */
import { useEffect, useMemo, useState } from 'react'
import { CalendarPlus, CircleNotch, Clock, CalendarBlank, BellRinging, X } from '@phosphor-icons/react'
import { MODELO_DO_LEMBRETE } from '@/lib/lembreteDaVisitaTexto'
import { useModoV3 } from '@/lib/modoV3'
import LembretesDaVisita from './LembretesDaVisita'
import { diaEmManaus, diaEmManausMais, horaEmManaus, instanteEmManaus } from '@/lib/fusoDeManaus'
import EscolherImovelDaVisita from './EscolherImovelDaVisita'
import { imovelPeloCodigo } from '@/lib/imovelDaVisita'

const AZUL = '#2563eb'
const AZUL_SUAVE = 'color-mix(in srgb, #2563eb 14%, transparent)'

interface Corretor { leadId: string; nome: string; fim: string }

const diaMais = (n: number) => diaEmManausMais(n)
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()

const DURACOES: Array<[number, string]> = [[30, '30 min'], [60, '1 h'], [90, '1h30'], [120, '2 h']]
/* por padrão, 1 hora antes (Pedro, 01/10) */
const ANTECEDENCIAS: Array<[number, string]> = [[30, '30 min antes'], [60, '1 hora antes'], [120, '2 horas antes'], [1440, '1 dia antes']]

export default function AgendarVisita({ imoveis, proprietarioLeadId, corretorInicial, codigoInicial, quandoInicial, aoAgendar, aoCancelar }: {
  /** os imóveis do dono deste card (aí o código é escolhido, não digitado) */
  imoveis?: string[]
  /** a conversa do proprietário: o lembrete dele sai por ela. SÓ no card do dono --
      num card de corretor, o lembrete do proprietário iria para a conversa errada. */
  proprietarioLeadId?: string
  /** aberto no card de um corretor: ele já vem escolhido (dá para trocar) */
  corretorInicial?: Corretor
  codigoInicial?: string
  /** dia/hora já escolhidos (o + da agenda pode abrir num horário) */
  quandoInicial?: Date
  aoAgendar?: (visita: number) => void
  aoCancelar?: () => void
}) {
  const [corretores, setCorretores] = useState<Corretor[]>([])
  const [codigo, setCodigo] = useState(codigoInicial || imoveis?.[0] || '')
  const [buscaCorretor, setBuscaCorretor] = useState('')
  const [corretor, setCorretor] = useState<Corretor | null>(corretorInicial || null)
  const [atalho, setAtalho] = useState<'hoje' | 'amanha' | 'data'>(quandoInicial ? 'data' : 'amanha')
  const [dia, setDia] = useState(() => (quandoInicial ? diaEmManaus(quandoInicial) : diaMais(1)))
  const [hora, setHora] = useState(() => (quandoInicial ? horaEmManaus(quandoInicial) : '10:00'))
  const [duracao, setDuracao] = useState(60)
  const [antes, setAntes] = useState(60)
  // desmarcados de propósito: o lembrete só existe para quem for marcado aqui
  const [paraCorretor, setParaCorretor] = useState(false)
  const [paraDono, setParaDono] = useState(false)
  const [mensagem, setMensagem] = useState(MODELO_DO_LEMBRETE)
  const [salvando, setSalvando] = useState(false)
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null)
  // 20/10 (Pedro: "ao criar uma visita quero uma opção excluir lembrete"): a visita que acabou de nascer, para o Excluir lembrete
  const [agendada, setAgendada] = useState<{ id: number; comLembrete: boolean } | null>(null)

  useEffect(() => {
    let vivo = true
    fetch('/api/parceria/visitas/opcoes')
      .then((r) => (r.ok ? r.json() : { corretores: [] }))
      .then((j) => { if (vivo) setCorretores(Array.isArray(j.corretores) ? j.corretores : []) })
      .catch(() => {})
    return () => { vivo = false }
  }, [])

  /* no card do dono os imóveis são os dele: o nome de cada um ao lado do código */
  const [nomes, setNomes] = useState<Record<string, string>>({})
  const chaveDosImoveis = (imoveis || []).join(',')
  useEffect(() => {
    if (!chaveDosImoveis) return
    const ctl = new AbortController()
    for (const c of chaveDosImoveis.split(',')) {
      imovelPeloCodigo(c, ctl.signal)
        .then((i) => { if (i && !ctl.signal.aborted) setNomes((n) => ({ ...n, [c]: i.nome })) })
        .catch(() => {})
    }
    return () => ctl.abort()
  }, [chaveDosImoveis])

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

  const comLembrete = paraCorretor || paraDono

  async function agendar() {
    if (salvando) return
    if (!/^\d{1,6}$/.test(codigo.trim())) { setAviso({ ok: false, texto: 'Escolha o imóvel na lista, ou digite o código dele.' }); return }
    if (!corretor && !numeroDigitado) { setAviso({ ok: false, texto: 'Escolha o corretor na lista ou digite o número dele com DDD.' }); return }
    // o dia e a hora do formulário são os de MANAUS, não os do relógio deste computador
    const quando = instanteEmManaus(dia, hora)
    if (Number.isNaN(quando.getTime())) { setAviso({ ok: false, texto: 'Escolha o dia e a hora.' }); return }
    setSalvando(true); setAviso(null); setAgendada(null)
    try {
      const r = await fetch('/api/parceria/visitas', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          codigo: Number(codigo.trim()),
          corretor: corretor ? { leadId: corretor.leadId, nome: corretor.nome } : { telefone: numeroDigitado },
          quando: quando.toISOString(),
          duracaoMin: duracao,
          lembrete: comLembrete
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
      } else if (!comLembrete) {
        partes.push('Sem lembrete: ninguém foi marcado.')
      }
      if (Array.isArray(j.avisos)) partes.push(...j.avisos)
      setAviso({ ok: true, texto: partes.join(' ') })
      setAgendada({ id: Number(j.visita), comLembrete: Array.isArray(j.lembretes) && j.lembretes.length > 0 })
      setMensagem(MODELO_DO_LEMBRETE)
      aoAgendar?.(Number(j.visita))
    } catch (e: any) {
      setAviso({ ok: false, texto: e?.message || 'Não consegui agendar.' })
    } finally { setSalvando(false) }
  }

  // v3 (Pedro, 04/11: "um único botão primário por seção, com a mesma cor de destaque; unifique"): o azul vira o destaque
  const v3 = useModoV3()
  const DESTAQUE = v3 ? 'var(--wa-green)' : AZUL
  const TINTA = v3 ? 'var(--wa-green-ink)' : '#fff'
  const campo = { background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }
  const chip = (ligado: boolean) => (ligado
    ? { background: DESTAQUE, color: TINTA }
    : { color: 'var(--wa-text-2)', border: '1px solid var(--wa-divider)' })
  const classeChip = 'inline-flex items-center gap-1 h-7 px-2.5 rounded-full text-[12.5px] font-medium'
  const rotulo = 'text-[12px] block mb-1'

  return (
    <div className="w-full text-left rounded-xl p-3" style={v3 ? { border: '1px solid var(--wa-divider)' } : { border: `1px solid ${AZUL}`, background: AZUL_SUAVE }}>
      <div className="flex items-center gap-1.5 mb-2">
        <CalendarPlus size={17} weight="fill" style={{ color: v3 ? 'var(--wa-text-2)' : AZUL }} />
        <b className="text-[14px]" style={{ color: v3 ? 'var(--wa-text)' : AZUL }}>Agendar visita</b>
        {aoCancelar && (
          <button type="button" onClick={aoCancelar} className="ml-auto wa-icone-btn !w-7 !h-7" aria-label="Fechar"><X size={15} /></button>
        )}
      </div>

      {/* o imóvel */}
      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Imóvel</label>
      {imoveis && imoveis.length > 0 ? (
        <div className="flex flex-wrap gap-1.5 mb-2.5">
          {imoveis.map((c) => (
            <button key={c} type="button" onClick={() => setCodigo(c)} aria-pressed={codigo === c}
                    className={`${classeChip} max-w-full`} style={chip(codigo === c)} title={nomes[c] ? `${c} · ${nomes[c]}` : undefined}>
              <span className="truncate">#{c}{nomes[c] ? ` ${nomes[c]}` : ''}</span>
            </button>
          ))}
        </div>
      ) : (
        <div className="mb-2.5">
          <EscolherImovelDaVisita codigo={codigo} aoMudar={setCodigo} estilo={campo} />
        </div>
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
      <label className={rotulo} style={{ color: 'var(--wa-text-2)' }}>Dia e hora <span style={{ opacity: 0.8 }}>(horário de Manaus)</span></label>
      <div className="flex flex-wrap items-center gap-1.5 mb-2.5">
        <button type="button" onClick={() => escolher('hoje')} aria-pressed={atalho === 'hoje'} className={classeChip} style={chip(atalho === 'hoje')}>Hoje</button>
        <button type="button" onClick={() => escolher('amanha')} aria-pressed={atalho === 'amanha'} className={classeChip} style={chip(atalho === 'amanha')}>Amanhã</button>
        <button type="button" onClick={() => escolher('data')} aria-pressed={atalho === 'data'} className={classeChip} style={chip(atalho === 'data')}><CalendarBlank size={14} /> Data</button>
        {atalho === 'data' && (
          // 450 (Pedro, 20/10): sem trava de dia; visita que já passou é só registro (o lembrete não sai)
          <input type="date" value={dia} onChange={(e) => setDia(e.target.value)} aria-label="Dia da visita"
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

      {/* o lembrete: ninguém marcado, 1 hora antes, e a mensagem padrão já escrita */}
      <p className="flex items-center gap-1.5 text-[13px] mb-1.5" style={{ color: 'var(--wa-text)' }}>
        <BellRinging size={15} style={{ color: AZUL }} /> Lembrete da visita
      </p>
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
        <textarea value={mensagem} onChange={(e) => setMensagem(e.target.value)} rows={3} maxLength={4000}
                  aria-label="Mensagem do lembrete"
                  className="w-full mt-1.5 rounded-lg px-2.5 py-1.5 text-[13px] leading-5 resize-y" style={campo} />
        <p className="text-[11px] mt-1 leading-4" style={{ color: 'var(--wa-text-2)' }}>
          {comLembrete
            ? <>Cada um recebe a mensagem com o seu nome, a hora e o imóvel no lugar de {'{nome}'}, {'{quando}'} e {'{imóvel}'}.</>
            : <>Marque <b>Corretor</b> e/ou <b>Proprietário</b> para mandar. Sem ninguém marcado, a visita entra na agenda sem lembrete.</>}
        </p>
      </div>

      <button type="button" onClick={() => void agendar()} disabled={salvando}
              className="inline-flex items-center gap-1.5 h-8 px-3.5 rounded-full text-[13px] font-semibold disabled:opacity-50"
              style={{ background: DESTAQUE, color: TINTA }}>
        {salvando ? <CircleNotch size={14} className="animate-spin" /> : <CalendarPlus size={14} weight="fill" />} Agendar visita
      </button>
      {aviso && <p className="text-[12.5px] mt-1.5 leading-4" style={{ color: aviso.ok ? AZUL : 'var(--wa-tag-tel)' }}>{aviso.texto}</p>}
      {agendada?.comLembrete && Number.isFinite(agendada.id) && <LembretesDaVisita key={agendada.id} visita={agendada.id} compacto />}
      <p className="text-[11px] mt-1.5 leading-4" style={{ color: 'var(--wa-text-2)' }}>
        Entra na agenda como visita da equipe: a Nay não manda nada sozinha, e o corretor fica na etapa Visitas até ela acabar.
      </p>
    </div>
  )
}
