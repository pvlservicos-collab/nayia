'use client'

/**
 * VISITA e PROPRIETÁRIOS (v2 do CRM, Pedro, 03/11/2026; lib/versaoDoCrm.ts): os dois números (Leads e Parceria) juntos, com a
 * faixa de qual número a conversa fala. A tela é a ChatJuntado (a cara do Leads).
 *
 * PROPRIETÁRIOS: os donos dos dois números. "Se tem conversa de dois números, prioridade é a Parceria": o mesmo telefone nos
 * dois aparece uma vez só, pela Parceria. Em cada conversa (03/11, noite) a faixa com o imóvel dele (o condomínio e o código)
 * e a borda da esquerda com o nome em pé de quem atende (lib/versaoDoCrm.ts, responsavelV2: quem assumiu; a Nay do número;
 * ou Rayssa na Parceria e Diego no Leads). Quem não é administrador abre em "Meus" (os dele) e tem "Todos"; o botão direito
 * "Assumir a conversa" faz dele o responsável.
 * Mais tarde, na mesma noite ("cada contato seja um card único ... e nem tem o nome dos condomínios deles ... os donos só
 * dos últimos 2 dias ... um espaço entre eles"): cada conversa é um card, com espaço entre eles (04/11: o corte de 2 dias
 * saiu, "deixa todos os proprietários lá"; a borda só em quem a Rayssa ou o Diego já têm); o nome do condomínio vem do banco (/api/imoveis-nay/nomes, 587), porque a Parceria só sabe o código.
 *
 * VISITA ("que fiquem só quem é visita, ou seja quem está relacionado a uma visita, ex.: o corretor ou lead e o proprietário
 * ... em cards de 2 contatos ou mais ... um ícone de calendário em cima escrito o horário sugerido da visita, se já está
 * confirmada ou não e com quem falta confirmar; entre uma visita e outra um espaço"): um card por visita aberta (as da
 * Parceria e as da Nay Leads, /api/parceria/visitas), com as conversas dela que existem no CRM.
 * Mais tarde ("tudo de visita é azul ... no + eu posso criar um relacionamento para visita manualmente, eu seleciono a
 * visita e os contatos por um buscador em um popup ... nos cards um menu em cima à direita: + adicionar pessoa e Status da
 * visita; o cancelado é vermelho e some o card, e o realizado é verde"):
 *   - o card é azul; a visita realizada fica verde por 24 h e sai; a cancelada some na hora
 *   - as conversas postas à mão na visita: custom_attributes.visitas_v2 (rota organizar { visita: { id, ligar } })
 *   - Status: Parceria pela agenda (/api/parceria/visitas/{id}: realizada | excluir, que a deixa cancelada sem avisar
 *     ninguém); Nay Leads por /api/leads/visitas/{id} (realizada, perguntando ao cliente ou ao corretor | cancelar, 587)
 *
 * FECHAMENTO (04/11: "uma nova aba fechamento que vai ser a última etapa após proprietários ... só o Tel vendo, a não ser
 * que ele inclua alguém como Rayssa ou Diego na conversa"): os leads em fechamento dos dois números (hooks/useFechamentoV2.ts),
 * um card por contato. O Tel vê todos e, no botão direito, inclui ou tira a Rayssa, o Diego... (custom_attributes.pessoas,
 * a mesma lista do "Adicionar pessoa"); quem foi incluído vê aqui só aqueles leads. Quem não pode ver um lead em
 * fechamento também não o acha nas outras abas da v2 (Proprietários aqui; Atendimento em /chat/atendimento).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CalendarBlank, CaretDown, Check, CheckCircle, Clock, MagnifyingGlass, Plus, UserCirclePlus, X, XCircle } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useCaptacaoDonos } from '@/hooks/useCaptacaoDonos'
import { useVisitasParceria } from '@/hooks/useVisitasParceria'
import type { LeadWithOwner } from '@/lib/types'
import type { VisitaNaTela } from '@/lib/tiposNay'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import { primeiroNome, responsavelV2 } from '@/lib/versaoDoCrm'
import { useEquipeV2 } from '@/hooks/useEquipeV2'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { pessoasDe } from '@/lib/organizacaoDoLead'
import ChatJuntado from './ChatJuntado'
import { casaNaBusca } from './BuscaDaLista'
import { imovelDoDono } from './LeadListItem'
import { organizar } from './OrganizarConversa'

const AZUL = '#2563eb'
const VERDE = '#16a34a'
const VERMELHO = '#dc2626'
const FIM_DA_VISITA = ['realizada', 'encerrada', 'cancelada', 'expirada']
const UM_DIA_MS = 24 * 3600 * 1000
const quandoDaVisita = (iso: string | null) => iso
  ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Manaus', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
  : 'sem horário'
const rotuloDaVisita = (v: VisitaNaTela) =>
  [quandoDaVisita(v.quando || v.quandoSugerido), [v.imovel, v.codigo ? `#${v.codigo}` : null].filter(Boolean).join(' ')].filter(Boolean).join(' · ')
const nomeDaConversa = (l: LeadWithOwner) => (l.title || '').trim() || l.phone || 'Sem nome'
const NUMERO: Record<string, string> = { captacao: 'Leads', parceria: 'Parceria' }

/** as visitas em que a conversa foi posta à mão (o id da Nay Leads é negativo) */
function visitasAMao(l: LeadWithOwner): number[] {
  const v = (l.custom_attributes as any)?.visitas_v2
  return Array.isArray(v) ? v.map(Number).filter((n) => Number.isInteger(n) && n !== 0) : []
}

/** com quem falta confirmar a visita */
function faltaConfirmar(v: VisitaNaTela): string[] {
  const falta: string[] = []
  if (v.linha === 'leads' && !v.clienteConfirmouEm) falta.push('o cliente')
  if (!v.confirmadaCorretorEm && (v.linha !== 'leads' || v.corretorNome)) falta.push('o corretor')
  if (!v.propOkEm) falta.push('o proprietário')
  return falta
}

type Status = { acao: 'realizada'; para?: 'cliente' | 'corretor' } | { acao: 'cancelada' }

function TopoDaVisita({ v, realizada, ocupado, aoAdicionar, aoStatus }: {
  v: VisitaNaTela; realizada: boolean; ocupado: boolean; aoAdicionar: () => void; aoStatus: (s: Status) => void
}) {
  const [aberto, setAberto] = useState(false)
  const caixa = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!aberto) return
    const fora = (e: MouseEvent) => { if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [aberto])
  const confirmada = v.estado === 'confirmada' || !!v.confirmadaEm
  const falta = confirmada ? [] : faltaConfirmar(v)
  const cor = realizada ? VERDE : AZUL
  const botao = 'h-7 px-2 rounded-md text-[12px] font-semibold flex items-center gap-1 flex-shrink-0 disabled:opacity-50'
  const item = 'w-full text-left px-3 py-2 text-[13px] hover:bg-[var(--wa-row-hover)] flex items-center gap-2'
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-1.5 font-semibold">
        <CalendarBlank size={16} weight="bold" style={{ color: cor }} />
        <span className="truncate">{quandoDaVisita(v.quando || v.quandoSugerido)}{!v.quando && v.quandoSugerido ? ' (sugerido)' : ''}</span>
        {realizada ? (
          <span className="ml-auto flex items-center gap-1 text-[12px] font-bold" style={{ color: VERDE }}>
            <CheckCircle size={15} weight="fill" /> Visita realizada
          </span>
        ) : (
          <div ref={caixa} className="ml-auto relative flex items-center gap-1">
            <button type="button" className={botao} disabled={ocupado} onClick={aoAdicionar}
                    style={{ color: AZUL, border: `1px solid ${AZUL}55` }} title="Pôr mais contatos neste card da visita">
              <Plus size={13} weight="bold" /> Adicionar pessoa
            </button>
            <button type="button" className={botao} disabled={ocupado} onClick={() => setAberto((x) => !x)}
                    style={{ color: '#fff', background: AZUL }} aria-expanded={aberto}>
              Status da visita <CaretDown size={12} weight="bold" />
            </button>
            {aberto && (
              <div className="absolute right-0 top-full mt-1 z-30 rounded-xl py-1.5 min-w-[250px] shadow-xl"
                   style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
                {v.linha === 'leads' ? (
                  <>
                    <button type="button" className={item} onClick={() => { setAberto(false); aoStatus({ acao: 'realizada', para: 'cliente' }) }}>
                      <CheckCircle size={16} weight="fill" style={{ color: VERDE }} /> Realizada <span className="ml-auto text-[11px]" style={{ color: 'var(--wa-text-2)' }}>a Nay pergunta ao cliente</span>
                    </button>
                    {v.corretorNome && (
                      <button type="button" className={item} onClick={() => { setAberto(false); aoStatus({ acao: 'realizada', para: 'corretor' }) }}>
                        <CheckCircle size={16} weight="fill" style={{ color: VERDE }} /> Realizada <span className="ml-auto text-[11px]" style={{ color: 'var(--wa-text-2)' }}>a Nay pergunta ao corretor</span>
                      </button>
                    )}
                  </>
                ) : (
                  <button type="button" className={item} onClick={() => { setAberto(false); aoStatus({ acao: 'realizada' }) }}>
                    <CheckCircle size={16} weight="fill" style={{ color: VERDE }} /> Realizada <span className="ml-auto text-[11px]" style={{ color: 'var(--wa-text-2)' }}>a Nay pergunta como foi</span>
                  </button>
                )}
                <button type="button" className={item} onClick={() => { setAberto(false); aoStatus({ acao: 'cancelada' }) }}>
                  <XCircle size={16} weight="fill" style={{ color: VERMELHO }} /> <span style={{ color: VERMELHO }}>Cancelada</span>
                  <span className="ml-auto text-[11px]" style={{ color: 'var(--wa-text-2)' }}>ninguém é avisado</span>
                </button>
              </div>
            )}
          </div>
        )}
      </div>
      <div className="text-[12px] flex items-center gap-1 flex-wrap" style={{ color: 'var(--wa-text-2)' }}>
        <span>{[v.imovel, v.codigo ? `#${v.codigo}` : null].filter(Boolean).join(' ')}{v.linha === 'leads' ? ' · Nay Leads' : ' · Parceria'}</span>
        {!realizada && (
          <span className="flex items-center gap-1 font-semibold" style={{ color: AZUL }}>
            · {confirmada ? <CheckCircle size={13} weight="fill" /> : <Clock size={13} weight="bold" />}
            {confirmada ? 'Confirmada' : 'Não confirmada'}
          </span>
        )}
        {falta.length > 0 && !realizada && <span>· falta confirmar: <b style={{ color: 'var(--wa-text)' }}>{falta.join(', ')}</b></span>}
      </div>
    </div>
  )
}

/** O popup do + e do "Adicionar pessoa": escolhe a visita e, pelo buscador, os contatos que entram no card dela. */
function RelacionarAVisita({ visitas, inicial, leads, aoFechar, aoMudar }: {
  visitas: VisitaNaTela[]; inicial: number | null; leads: LeadWithOwner[]; aoFechar: () => void
  aoMudar: (leadId: string, custom: Record<string, any>) => void
}) {
  const [vid, setVid] = useState<number | null>(inicial ?? visitas[0]?.id ?? null)
  const [busca, setBusca] = useState('')
  const [ocupado, setOcupado] = useState('')
  const [erro, setErro] = useState('')
  const dosNumeros = useMemo(() => leads.filter((l) => !l.is_group && ['captacao', 'parceria'].includes(getLinhaWhatsapp(l) || '')), [leads])
  const ja = vid == null ? [] : dosNumeros.filter((l) => visitasAMao(l).includes(vid))
  const achados = busca.trim().length < 2 ? [] : dosNumeros.filter((l) => casaNaBusca(busca, l)).slice(0, 25)
  const alternar = async (l: LeadWithOwner, ligar: boolean) => {
    if (vid == null) return
    setOcupado(l.id); setErro('')
    try {
      const o = await organizar(l.id, { visita: { id: vid, ligar } })
      aoMudar(l.id, o.custom_attributes)
    } catch (e: any) { setErro(e?.message || 'Não consegui salvar.') } finally { setOcupado('') }
  }
  const linhaDoContato = (l: LeadWithOwner) => {
    const dentro = vid != null && visitasAMao(l).includes(vid)
    return (
      <label key={l.id} className="flex items-center gap-2.5 px-3 py-2 rounded-lg cursor-pointer hover:bg-[var(--wa-row-hover)]">
        <input type="checkbox" checked={dentro} disabled={!!ocupado || vid == null} onChange={(e) => void alternar(l, e.target.checked)}
               style={{ accentColor: AZUL }} />
        <span className="flex-1 min-w-0">
          <span className="block text-[14px] truncate">{nomeDaConversa(l)}</span>
          <span className="block text-[11.5px]" style={{ color: 'var(--wa-text-2)' }}>{l.phone} · número {NUMERO[getLinhaWhatsapp(l) || ''] || ''}</span>
        </span>
        {ocupado === l.id && <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>salvando…</span>}
      </label>
    )
  }
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.45)' }} onMouseDown={aoFechar}>
      <div className="chat-theme w-full max-w-[520px] max-h-[85vh] flex flex-col rounded-2xl shadow-2xl overflow-hidden"
           style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)', border: `2px solid ${AZUL}` }} onMouseDown={(e) => e.stopPropagation()}>
        <div className="px-4 py-3 flex items-center gap-2" style={{ background: `color-mix(in srgb, ${AZUL} 12%, transparent)` }}>
          <CalendarBlank size={20} weight="bold" style={{ color: AZUL }} />
          <div className="flex-1">
            <div className="text-[16px] font-bold">Relacionar à visita</div>
            <div className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Escolha a visita e marque os contatos que entram no card dela</div>
          </div>
          <button type="button" onClick={aoFechar} className="wa-icone-btn" aria-label="Fechar"><X size={18} /></button>
        </div>
        <div className="p-4 flex flex-col gap-3 min-h-0 overflow-y-auto">
          <div>
            <div className="text-[12px] font-semibold mb-1" style={{ color: 'var(--wa-text-2)' }}>Visita</div>
            {visitas.length === 0 ? (
              <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Nenhuma visita aberta agora.</p>
            ) : (
              <select value={vid ?? ''} onChange={(e) => setVid(Number(e.target.value))}
                      className="w-full h-10 px-3 rounded-lg text-[14px]"
                      style={{ background: 'var(--wa-search)', color: 'var(--wa-text)', border: `1px solid ${AZUL}55` }}>
                {visitas.map((v) => <option key={v.id} value={v.id}>{rotuloDaVisita(v)}{v.linha === 'leads' ? ' · Nay Leads' : ' · Parceria'}</option>)}
              </select>
            )}
          </div>
          {ja.length > 0 && (
            <div>
              <div className="text-[12px] font-semibold mb-1" style={{ color: 'var(--wa-text-2)' }}>Já postos à mão nesta visita</div>
              <div className="flex flex-col">{ja.map(linhaDoContato)}</div>
            </div>
          )}
          <div>
            <div className="text-[12px] font-semibold mb-1" style={{ color: 'var(--wa-text-2)' }}>Contatos</div>
            <label className="wa-busca">
              <MagnifyingGlass size={18} />
              <input autoFocus value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar nome ou número" aria-label="Buscar contatos" />
            </label>
            <div className="flex flex-col mt-1">
              {busca.trim().length >= 2 && achados.length === 0 && (
                <p className="px-3 py-2 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Ninguém com esse nome ou número nos números Leads e Parceria.</p>
              )}
              {achados.filter((l) => !ja.includes(l)).map(linhaDoContato)}
            </div>
          </div>
          {erro && <p className="text-[13px]" style={{ color: VERMELHO }}>{erro}</p>}
        </div>
        <div className="px-4 py-3 flex justify-end" style={{ borderTop: '1px solid var(--wa-divider)' }}>
          <button type="button" onClick={aoFechar} className="h-9 px-4 rounded-lg text-[14px] font-semibold" style={{ background: AZUL, color: '#fff' }}>Pronto</button>
        </div>
      </div>
    </div>
  )
}

export default function ChatPorEtapa({ etapa }: { etapa: 'visita' | 'proprietarios' | 'fechamento' }) {
  const { isMaster, roleName, permissions, profileName, user } = useAuth()
  const admin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const eu = primeiroNome(profileName || user?.name)
  const { leads, setLeads } = useLeadsContext()
  const { ehProprietario } = usePapelDoContato()
  const { marcas } = useParceriaMarcas(true)
  const donos = useCaptacaoDonos(etapa === 'proprietarios')
  const { visitas, recarregar } = useVisitasParceria(etapa === 'visita')
  const [assumindo, setAssumindo] = useState('')
  const { emFechamento, podeVer } = useFechamentoV2()

  /* ── Proprietários ── */
  const daEtapa = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    return (linha === 'captacao' || linha === 'parceria') && ehProprietario(l)
  }, [ehProprietario])
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria' && daEtapa(l))
    .map((l) => fim8(l.phone)).filter(Boolean)), [leads, daEtapa])
  // 04/11 (Pedro: "deixa todos os proprietários lá no Donos"): saiu o corte de 2 dias de 03/11
  const ehDono = useCallback((l: LeadWithOwner) => daEtapa(l) && podeVer(l)
    && !(getLinhaWhatsapp(l) === 'captacao' && pelaParceria.has(fim8(l.phone))), [daEtapa, pelaParceria, podeVer])

  /* o nome do condomínio de cada código da Parceria (a marca só traz o código) */
  const [nomes, setNomes] = useState<Record<number, string>>({})
  const codigosDaParceria = useMemo(() => etapa !== 'proprietarios' ? '' : Array.from(new Set(leads
    .filter((l) => getLinhaWhatsapp(l) === 'parceria' && ehDono(l))
    .flatMap((l) => (marcas[l.id]?.imoveisDoDono || []).map(Number)).filter((n) => Number.isInteger(n) && n > 0)))
    .sort((a, b) => a - b).join(','), [etapa, leads, marcas, ehDono])
  useEffect(() => {
    if (!codigosDaParceria) return
    let vivo = true
    fetch(`/api/imoveis-nay/nomes?codigos=${codigosDaParceria}`).then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (vivo && j?.nomes) setNomes((n) => ({ ...n, ...j.nomes })) }).catch(() => {})
    return () => { vivo = false }
  }, [codigosDaParceria])

  // 04/11: a borda só de quem já tem a Rayssa ou o Diego (assumiu ou mandou mensagem); os outros, sem borda
  const equipe = useEquipeV2(etapa === 'proprietarios' || etapa === 'fechamento')
  const quemAtende = useCallback((l: LeadWithOwner) => responsavelV2(l as any, equipe), [equipe])
  const imovelDele = useCallback((l: LeadWithOwner): string | null => {
    if (getLinhaWhatsapp(l) === 'parceria') {
      const i = marcas[l.id]?.imoveisDoDono || []
      const rotulo = (c: string) => [nomes[Number(c)], `#${c}`].filter(Boolean).join(' ')
      return i.length ? i.slice(0, 2).map(rotulo).join(' · ') + (i.length > 2 ? ` +${i.length - 2}` : '') : null
    }
    return imovelDoDono(donos[l.id]) || null
  }, [marcas, donos, nomes])

  const assumir = async (l: LeadWithOwner) => {
    setAssumindo(l.id)
    try {
      const o = await organizar(l.id, { responsavel: { nome: profileName || user?.name || '' } })
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
    } catch (e: any) { window.alert(e?.message || 'Não consegui assumir.') } finally { setAssumindo('') }
  }

  /* ── Visita ── */
  // o que acabou de ser marcado aqui vale na hora, antes da próxima leitura das visitas
  const [marcadas, setMarcadas] = useState<Record<number, 'realizada' | 'cancelada'>>({})
  const [mexendo, setMexendo] = useState<number | null>(null)
  const [popup, setPopup] = useState<{ visita: number | null } | null>(null)
  const realizada = useCallback((v: VisitaNaTela) => marcadas[v.id] === 'realizada'
    || ((v.estado === 'realizada' || !!v.realizadaEm)
        && Date.now() - new Date(v.realizadaEm || v.posVisitaEm || v.atualizadoEm || 0).getTime() < UM_DIA_MS), [marcadas])
  const naTela = useMemo(() => visitas
    .filter((v) => marcadas[v.id] !== 'cancelada' && ((v.aberta && !FIM_DA_VISITA.includes(v.estado)) || realizada(v)))
    .sort((a, b) => new Date(a.quando || a.quandoSugerido || 0).getTime() - new Date(b.quando || b.quandoSugerido || 0).getTime()),
  [visitas, marcadas, realizada])
  const abertas = useMemo(() => naTela.filter((v) => !realizada(v)), [naTela, realizada])

  /** as conversas de cada visita: a do corretor (ou do cliente), a do dono, na Nay Leads o cliente e o corretor pelo número,
   *  e as postas à mão */
  const conversasDaVisita = useMemo(() => {
    const porTelefone = (tel: string | null | undefined) => {
      const f = fim8(tel)
      if (!f) return []
      const doTel = leads.filter((l) => !l.is_group && fim8(l.phone) === f && ['parceria', 'captacao'].includes(getLinhaWhatsapp(l) || ''))
      const parceria = doTel.find((l) => getLinhaWhatsapp(l) === 'parceria')
      return parceria ? [parceria.id] : doTel.map((l) => l.id).slice(0, 1)
    }
    const aMao = new Map<number, string[]>()
    for (const l of leads) for (const vid of visitasAMao(l)) aMao.set(vid, [...(aMao.get(vid) || []), l.id])
    const m = new Map<number, string[]>()
    for (const v of naTela) {
      const ids = [v.conversa?.leadId, ...porTelefone(v.clienteTelefone), ...porTelefone(v.corretorTelefone), v.dono?.leadId,
                   ...porTelefone(v.dono?.telefone), ...(aMao.get(v.id) || [])]
      m.set(v.id, Array.from(new Set(ids.filter(Boolean) as string[])))
    }
    return m
  }, [naTela, leads])
  /* 04/11 (Pedro: "o Diego, da equipe, fica fixado fora dos cards de visita ... ele não fica relacionado, fica no topo, antes
     de começar os cards"): quem acompanha as visitas (a marca acompanhante da Parceria, a mesma que fixa no topo de Visitas
     na v1) fica em cima, fora dos cards */
  const acompanhantes = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria'
    && marcas[l.id]?.acompanhante).map((l) => l.id)), [leads, marcas])
  const daVisita = useMemo(() => new Set(Array.from(conversasDaVisita.values()).flat()), [conversasDaVisita])
  const naVisita = useCallback((l: LeadWithOwner) => daVisita.has(l.id) || acompanhantes.has(l.id), [daVisita, acompanhantes])

  const mudarStatus = async (v: VisitaNaTela, s: Status) => {
    if (s.acao === 'cancelada' && !window.confirm(`Cancelar a visita de ${rotuloDaVisita(v)}? Ninguém é avisado, e o card some.`)) return
    setMexendo(v.id)
    try {
      const leadsDaNay = v.id < 0
      const r = await fetch(leadsDaNay ? `/api/leads/visitas/${-v.id}` : `/api/parceria/visitas/${v.id}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(s.acao === 'cancelada'
          ? { acao: leadsDaNay ? 'cancelar' : 'excluir' }
          : leadsDaNay ? { acao: 'realizada', para: s.para || 'cliente' } : { acao: 'realizada' }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || j?.ok === false) throw new Error(j?.mensagem || j?.error || 'Não consegui mudar a visita.')
      setMarcadas((m) => ({ ...m, [v.id]: s.acao }))
      void recarregar()
    } catch (e: any) { window.alert(e?.message || 'Não consegui mudar a visita.') } finally { setMexendo(null) }
  }

  /* ── Fechamento ── */
  const naFechamento = useCallback((l: LeadWithOwner) => ['captacao', 'parceria'].includes(getLinhaWhatsapp(l) || '')
    && emFechamento(l) && podeVer(l), [emFechamento, podeVer])
  // quem o Tel pode incluir: a equipe, menos ele mesmo
  const incluiveis = useMemo(() => Object.entries(equipe).filter(([, p]) => p.chave !== 'tel')
    .sort((a, b) => a[1].nome.localeCompare(b[1].nome, 'pt-BR')), [equipe])
  const [incluindo, setIncluindo] = useState('')
  const incluir = async (l: LeadWithOwner, membro: string) => {
    const atuais = pessoasDe(l)
    const novas = atuais.includes(membro) ? atuais.filter((x) => x !== membro) : [...atuais, membro]
    setIncluindo(l.id)
    try {
      const o = await organizar(l.id, { pessoas: novas })
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
    } catch (e: any) { window.alert(e?.message || 'Não consegui incluir.') } finally { setIncluindo('') }
  }

  if (etapa === 'fechamento') {
    return (
      <ChatJuntado titulo="Fechamento"
                   subtitulo={admin ? 'Os leads em fechamento dos dois números · só você vê, e quem você incluir (botão direito)'
                                    : 'Os leads em fechamento em que o Tel te incluiu'}
                   pertence={naFechamento} chaveAbas="crm:abas-fechamento" cards
                   vazio={admin ? 'Nenhum lead em fechamento agora.' : 'O Tel ainda não te incluiu em nenhum lead em fechamento.'}
                   enfeite={(l) => ({ borda: quemAtende(l) })}
                   menu={admin ? (lead, fechar) => (
                     <div className="flex flex-col">
                       <div className="px-4 pt-1 pb-1.5 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
                         Incluir na conversa (passa a ver no Fechamento)
                       </div>
                       {incluiveis.length === 0 && <div className="px-4 py-2 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Carregando a equipe…</div>}
                       {incluiveis.map(([id, p]) => {
                         const dentro = pessoasDe(lead).includes(id)
                         return (
                           <button key={id} type="button" disabled={!!incluindo}
                                   className="w-full text-left px-4 py-2 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3 disabled:opacity-50"
                                   onClick={() => { fechar(); void incluir(lead, id) }}>
                             <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: p.cor }} />
                             <span className="flex-1">{p.nome}</span>
                             {dentro && <Check size={15} weight="bold" style={{ color: p.cor }} />}
                             <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>{dentro ? 'tirar' : 'incluir'}</span>
                           </button>
                         )
                       })}
                     </div>
                   ) : undefined} />
    )
  }

  if (etapa === 'visita') {
    return (
      <>
        <ChatJuntado titulo="Visita" subtitulo="Cada visita num card: o corretor ou o cliente e o proprietário · a resposta sai pelo número de cada conversa"
                     pertence={naVisita} chaveAbas="crm:abas-visita" vazio="Nenhuma visita aberta agora."
                     botaoMais={{ titulo: 'Relacionar contatos a uma visita', aoClicar: () => setPopup({ visita: null }) }}
                     fixos={{ rotulo: 'Equipe', ids: acompanhantes }}
                     grupos={(visiveis) => {
                       const ids = new Set(visiveis.map((l) => l.id))
                       return naTela.map((v) => ({
                         chave: String(v.id), cor: realizada(v) ? VERDE : AZUL,
                         topo: <TopoDaVisita v={v} realizada={realizada(v)} ocupado={mexendo === v.id}
                                             aoAdicionar={() => setPopup({ visita: v.id })} aoStatus={(s) => void mudarStatus(v, s)} />,
                         leads: (conversasDaVisita.get(v.id) || []).filter((id) => ids.has(id)).map((id) => visiveis.find((l) => l.id === id)!),
                       })).filter((g) => g.leads.length > 0)
                     }} />
        {popup && (
          <RelacionarAVisita visitas={abertas} inicial={popup.visita} leads={leads} aoFechar={() => setPopup(null)}
                             aoMudar={(leadId, custom) => setLeads((p) => p.map((x) => (x.id === leadId ? { ...x, custom_attributes: custom } : x)))} />
        )}
      </>
    )
  }
  return (
    <ChatJuntado titulo="Proprietários" subtitulo="Os donos dos dois números · a resposta sai pelo número de cada conversa"
                 pertence={ehDono} chaveAbas="crm:abas-proprietarios" vazio="Nenhum proprietário agora."
                 cards
                 enfeite={(l) => ({ faixa: imovelDele(l), borda: quemAtende(l) })}
                 meus={admin ? undefined : (l) => quemAtende(l)?.chave === eu}
                 menu={(lead, fechar) => (
                   <button type="button" disabled={!!assumindo}
                           className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3 disabled:opacity-50"
                           title="Você passa a ser quem atende este proprietário"
                           onClick={() => { fechar(); void assumir(lead) }}>
                     <UserCirclePlus size={17} style={{ color: 'var(--wa-icon)' }} /> Assumir a conversa
                     <span className="ml-auto text-[12px]" style={{ color: 'var(--wa-text-2)' }}>hoje: {quemAtende(lead)?.nome || 'ninguém'}</span>
                   </button>
                 )} />
  )
}
