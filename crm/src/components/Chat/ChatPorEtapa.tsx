'use client'

/**
 * VISITA e PROPRIETÁRIOS (v2 do CRM, Pedro, 03/11/2026; lib/versaoDoCrm.ts): os dois números (Leads e Parceria) juntos, com a
 * faixa de qual número a conversa fala. A tela é a ChatJuntado (a cara do Leads).
 *
 * PROPRIETÁRIOS: todos os donos dos dois números. "Se tem conversa de dois números, prioridade é a Parceria": o mesmo
 * telefone nos dois aparece uma vez só, pela Parceria. Em cada conversa (03/11, noite) a faixa preta/branca com o imóvel
 * dele e o código, e a borda da esquerda com o nome em pé de quem atende (lib/versaoDoCrm.ts, responsavelV2: quem assumiu;
 * a Nay do número; ou Rayssa na Parceria e Diego no Leads). Quem não é administrador abre em "Meus" (os dele) e tem "Todos";
 * o botão direito "Assumir a conversa" faz dele o responsável.
 *
 * VISITA (03/11, noite: "que fiquem só quem é visita, ou seja quem está relacionado a uma visita, ex.: o corretor ou lead e o
 * proprietário ... em cards de 2 contatos ou mais, com uma bordinha verde, um ícone de calendário em cima escrito o horário
 * sugerido da visita, se já está confirmada ou não e com quem falta confirmar; entre uma visita e outra um espaço"): um card
 * por visita aberta (as da Parceria e as da Nay Leads, /api/parceria/visitas), com as conversas dela que existem no CRM.
 */
import { useCallback, useMemo, useState } from 'react'
import { CalendarBlank, CheckCircle, Clock, UserCirclePlus } from '@phosphor-icons/react'
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
import { nayEmPausa } from '@/lib/etapaDaParceria'
import { primeiroNome, responsavelV2 } from '@/lib/versaoDoCrm'
import ChatJuntado from './ChatJuntado'
import { imovelDoDono } from './LeadListItem'
import { organizar } from './OrganizarConversa'

const FIM_DA_VISITA = ['realizada', 'encerrada', 'cancelada', 'expirada']
const quandoDaVisita = (iso: string | null) => iso
  ? new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Manaus', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
  : 'sem horário'

/** com quem falta confirmar a visita */
function faltaConfirmar(v: VisitaNaTela): string[] {
  const falta: string[] = []
  if (v.linha === 'leads' && !v.clienteConfirmouEm) falta.push('o cliente')
  if (!v.confirmadaCorretorEm && (v.linha !== 'leads' || v.corretorNome)) falta.push('o corretor')
  if (!v.propOkEm) falta.push('o proprietário')
  return falta
}

function TopoDaVisita({ v }: { v: VisitaNaTela }) {
  const confirmada = v.estado === 'confirmada' || !!v.confirmadaEm
  const falta = confirmada ? [] : faltaConfirmar(v)
  return (
    <div className="flex flex-col gap-0.5">
      <div className="flex items-center gap-1.5 font-semibold">
        <CalendarBlank size={16} weight="bold" style={{ color: '#16a34a' }} />
        <span>{quandoDaVisita(v.quando || v.quandoSugerido)}{!v.quando && v.quandoSugerido ? ' (sugerido)' : ''}</span>
        <span className="ml-auto flex items-center gap-1 text-[12px]" style={{ color: confirmada ? '#16a34a' : '#d97706' }}>
          {confirmada ? <CheckCircle size={14} weight="fill" /> : <Clock size={14} weight="bold" />}
          {confirmada ? 'Confirmada' : 'Não confirmada'}
        </span>
      </div>
      <div className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
        {[v.imovel, v.codigo ? `#${v.codigo}` : null].filter(Boolean).join(' ')}
        {v.linha === 'leads' ? ' · Nay Leads' : ' · Parceria'}
        {falta.length > 0 && <> · falta confirmar: <b style={{ color: 'var(--wa-text)' }}>{falta.join(', ')}</b></>}
      </div>
    </div>
  )
}

export default function ChatPorEtapa({ etapa }: { etapa: 'visita' | 'proprietarios' }) {
  const { isMaster, roleName, permissions, profileName, user } = useAuth()
  const admin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const eu = primeiroNome(profileName || user?.name)
  const { leads, setLeads } = useLeadsContext()
  const { ehProprietario } = usePapelDoContato()
  const { marcas } = useParceriaMarcas(true)
  const donos = useCaptacaoDonos(etapa === 'proprietarios')
  const { visitas } = useVisitasParceria(etapa === 'visita')
  const [assumindo, setAssumindo] = useState('')

  /* ── Proprietários ── */
  const daEtapa = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    return (linha === 'captacao' || linha === 'parceria') && ehProprietario(l)
  }, [ehProprietario])
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria' && daEtapa(l))
    .map((l) => fim8(l.phone)).filter(Boolean)), [leads, daEtapa])
  const ehDono = useCallback((l: LeadWithOwner) => daEtapa(l)
    && !(getLinhaWhatsapp(l) === 'captacao' && pelaParceria.has(fim8(l.phone))), [daEtapa, pelaParceria])

  const quemAtende = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    const m = marcas[l.id]
    return responsavelV2(l as any, linha, linha === 'parceria' && !!(m?.telAtendendo || nayEmPausa(m)))
  }, [marcas])
  const imovelDele = useCallback((l: LeadWithOwner): string | null => {
    if (getLinhaWhatsapp(l) === 'parceria') {
      const i = marcas[l.id]?.imoveisDoDono || []
      return i.length ? i.slice(0, 2).join(' · ') + (i.length > 2 ? ` +${i.length - 2}` : '') : null
    }
    return imovelDoDono(donos[l.id]) || null
  }, [marcas, donos])

  const assumir = async (l: LeadWithOwner) => {
    setAssumindo(l.id)
    try {
      const o = await organizar(l.id, { responsavel: { nome: profileName || user?.name || '' } })
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
    } catch (e: any) { window.alert(e?.message || 'Não consegui assumir.') } finally { setAssumindo('') }
  }

  /* ── Visita ── */
  const abertas = useMemo(() => visitas.filter((v) => v.aberta && !FIM_DA_VISITA.includes(v.estado))
    .sort((a, b) => new Date(a.quando || a.quandoSugerido || 0).getTime() - new Date(b.quando || b.quandoSugerido || 0).getTime()), [visitas])
  /** as conversas de cada visita: a do corretor (ou do cliente), a do dono e, na Nay Leads, o cliente e o corretor pelo número */
  const conversasDaVisita = useMemo(() => {
    const porTelefone = (tel: string | null | undefined) => {
      const f = fim8(tel)
      if (!f) return []
      const doTel = leads.filter((l) => !l.is_group && fim8(l.phone) === f && ['parceria', 'captacao'].includes(getLinhaWhatsapp(l) || ''))
      const parceria = doTel.find((l) => getLinhaWhatsapp(l) === 'parceria')
      return parceria ? [parceria.id] : doTel.map((l) => l.id).slice(0, 1)
    }
    const m = new Map<number, string[]>()
    for (const v of abertas) {
      const ids = [v.conversa?.leadId, ...porTelefone(v.clienteTelefone), ...porTelefone(v.corretorTelefone), v.dono?.leadId, ...porTelefone(v.dono?.telefone)]
      m.set(v.id, Array.from(new Set(ids.filter(Boolean) as string[])))
    }
    return m
  }, [abertas, leads])
  const daVisita = useMemo(() => new Set(Array.from(conversasDaVisita.values()).flat()), [conversasDaVisita])
  const naVisita = useCallback((l: LeadWithOwner) => daVisita.has(l.id), [daVisita])

  if (etapa === 'visita') {
    return (
      <ChatJuntado titulo="Visita" subtitulo="Cada visita aberta num card: o corretor ou o cliente e o proprietário · a resposta sai pelo número de cada conversa"
                   pertence={naVisita} chaveAbas="crm:abas-visita" vazio="Nenhuma visita aberta agora."
                   grupos={(visiveis) => {
                     const ids = new Set(visiveis.map((l) => l.id))
                     return abertas.map((v) => ({
                       chave: String(v.id), topo: <TopoDaVisita v={v} />,
                       leads: (conversasDaVisita.get(v.id) || []).filter((id) => ids.has(id)).map((id) => visiveis.find((l) => l.id === id)!),
                     })).filter((g) => g.leads.length > 0)
                   }} />
    )
  }
  return (
    <ChatJuntado titulo="Proprietários" subtitulo="Os donos dos dois números, num lugar só · a resposta sai pelo número de cada conversa"
                 pertence={ehDono} chaveAbas="crm:abas-proprietarios" vazio="Nenhum proprietário agora."
                 enfeite={(l) => ({ faixa: imovelDele(l), borda: quemAtende(l) })}
                 meus={admin ? undefined : (l) => quemAtende(l).chave === eu}
                 menu={(lead, fechar) => (
                   <button type="button" disabled={!!assumindo}
                           className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3 disabled:opacity-50"
                           title="Você passa a ser quem atende este proprietário"
                           onClick={() => { fechar(); void assumir(lead) }}>
                     <UserCirclePlus size={17} style={{ color: 'var(--wa-icon)' }} /> Assumir a conversa
                     <span className="ml-auto text-[12px]" style={{ color: 'var(--wa-text-2)' }}>hoje: {quemAtende(lead).nome}</span>
                   </button>
                 )} />
  )
}
