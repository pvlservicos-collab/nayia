'use client'

/**
 * CHAT ADMINISTRAÇÃO (Pedro, 03/11/2026): "um chat de administração lá em cima que vai reunir todas as pessoas nessa etapa
 * dos 2 números, com aquele disclaimerzinho de qual número ele fala, para o Tel atender todos de administração por lá; só
 * vai estar disponível para o usuário Tel; as etapas são só Todos e Não lidos; quando o Tel digitar vai sair pelo número,
 * como se fosse pelo chat do número; e põe tags lá também, mas outras tags, zeradas, que ele pode clicar".
 *
 * Quem entra: o tipo de contato Administração, nos dois números (03/11, à tarde, Pedro: "volte as etapas que estão
 * Administração nos números para Fechamento ... os marcados como Administração só quem pode ver é o Tel"). A etiqueta e a
 * etapa Fechamento voltaram a ser Fechamento, que a equipe toda vê, e não trazem mais ninguém para cá.
 * Cada conversa continua sendo da linha dela (crm/CLAUDE.md): a faixa diz por qual número fala, e a resposta sai por ele.
 * As etiquetas desta tela (as abas depois de Todos e Não lidos) são escolhidas aqui e começam vazias; ficam neste navegador.
 *
 * O BOTÃO DIREITO (Pedro, 03/11: "uma opção de tirar o lead quando eu clicar com o botão direito e voltar ele ao contato
 * como Todos, ou Proprietário, ou Fechamento"): o tipo Administração sai e a conversa volta às abas do número dela --
 *   Todos         sem tipo escolhido (vale o que a lista deduz); na Parceria, a etapa Todos do card
 *   Proprietário  o tipo Proprietário; na Parceria, a etapa Proprietários do card
 *   Fechamento    no Leads, a etiqueta Fechamento (que move o card para a etapa fechamento); na Parceria, a etapa do card
 * Na Parceria vai pela rota do card (/api/leads/[id]/contato), que também avisa a Nay, como quem escolhe no card.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { CircleNotch, FolderSimpleUser, Plus, X } from '@phosphor-icons/react'
import { useAuth } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useTiposDeContato } from '@/hooks/useTiposDeContato'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { acharTipo, tipoEscolhido } from '@/lib/organizacaoDoLead'
import { CORES_DE_ETIQUETA, criarEtiqueta, useEtiquetas } from '@/lib/etiquetas'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LeadListItem, { ehEtapaComoTag } from './LeadListItem'
import ChatWindow from './ChatWindow'
import { organizar } from './OrganizarConversa'

const CHAVE_ABAS = 'crm:abas-administracao'
const NUMERO: Record<string, string> = { captacao: 'Pelo número Leads · 8595-6408', parceria: 'Pelo número Parceria · 9445-3618' }
type Volta = 'todos' | 'proprietarios' | 'fechamento'
const VOLTAS: { chave: Volta; rotulo: string }[] = [
  { chave: 'todos', rotulo: 'Todos' }, { chave: 'proprietarios', rotulo: 'Proprietário' }, { chave: 'fechamento', rotulo: 'Fechamento' },
]

function hora(iso?: string) {
  if (!iso) return ''
  const d = new Date(iso)
  const hoje = new Date()
  return d.toDateString() === hoje.toDateString()
    ? d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
    : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' })
}

export default function ChatAdministracao() {
  const { organizationId, loading, isMaster, roleName, permissions } = useAuth()
  const ehAdmin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const { leads, setLeads } = useLeadsContext()
  const { marcas } = useParceriaMarcas(true)
  const { tipos } = useTiposDeContato()
  const etiquetas = useEtiquetas()
  const idFechamento = etiquetas.find((t) => (t.nomeOriginal || t.name) === 'Fechamento')?.id

  const [aba, setAba] = useState<string>('todos')
  const [selecionada, setSelecionada] = useState<string | null>(null)
  const [abas, setAbas] = useState<string[]>([])
  const [escolhendo, setEscolhendo] = useState(false)
  const [menu, setMenu] = useState<{ x: number; y: number; lead: LeadWithOwner } | null>(null)
  const [tirando, setTirando] = useState('')
  useEffect(() => {
    if (!menu) return
    const fechar = () => setMenu(null)
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') setMenu(null) }
    window.addEventListener('click', fechar)
    window.addEventListener('scroll', fechar, true)
    window.addEventListener('keydown', tecla)
    return () => { window.removeEventListener('click', fechar); window.removeEventListener('scroll', fechar, true); window.removeEventListener('keydown', tecla) }
  }, [menu])
  useEffect(() => { try { setAbas(JSON.parse(localStorage.getItem(CHAVE_ABAS) || '[]')) } catch {} }, [])
  const salvarAbas = (novas: string[]) => { setAbas(novas); try { localStorage.setItem(CHAVE_ABAS, JSON.stringify(novas)) } catch {} }

  const daAdministracao = useCallback((l: LeadWithOwner) => {
    if (l.is_group || l.is_archived) return false
    const linha = getLinhaWhatsapp(l)
    return (linha === 'captacao' || linha === 'parceria') && acharTipo(tipos, tipoEscolhido(l))?.chave === 'administracao'
  }, [tipos])

  /** tira da Administração e devolve a conversa às abas do número dela (ver o cabeçalho) */
  const tirar = async (l: LeadWithOwner, volta: Volta) => {
    setMenu(null); setTirando(l.id)
    try {
      const linha = getLinhaWhatsapp(l)
      if (linha === 'parceria') {
        const r = await fetch(`/api/leads/${l.id}/contato`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: volta }),
        })
        const j = await r.json().catch(() => ({}))
        if (!r.ok) throw new Error(j.error || j.message || 'Não consegui mudar a etapa.')
      } else if (volta === 'fechamento') {
        if (!idFechamento) throw new Error('Não achei a etiqueta Fechamento.')
        const r = await fetch(`/api/leads/${l.id}/tags`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tag_id: idFechamento }),
        })
        if (!r.ok) throw new Error('Não consegui pôr a etiqueta Fechamento.')
      }
      // por último o tipo: a resposta traz o custom_attributes inteiro, já com a etapa da Parceria
      const o = await organizar(l.id, { tipo: volta === 'proprietarios' ? 'proprietario' : null })
      setLeads((p) => p.map((x) => x.id !== l.id ? x : {
        ...x, custom_attributes: o.custom_attributes,
        lead_tags: linha === 'captacao' && volta === 'fechamento' && idFechamento && !(x.lead_tags || []).some((lt: any) => lt.tag_id === idFechamento)
          ? [...(x.lead_tags || []), { tag_id: idFechamento } as any] : x.lead_tags,
      }))
      if (selecionada === l.id) setSelecionada(null)
    } catch (e: any) {
      window.alert(e?.message || 'Não consegui tirar da Administração.')
    } finally { setTirando('') }
  }

  const todas = useMemo(() => leads.filter(daAdministracao)
    .sort((a, b) => new Date(b.last_activity_at || b.created_at).getTime() - new Date(a.last_activity_at || a.created_at).getTime()),
  [leads, daAdministracao])
  const contagem = (tagId: string) => todas.filter((l) => (l.lead_tags || []).some((lt: any) => lt.tag_id === tagId)).length
  const visiveis = todas.filter((l) => aba === 'todos' ? true : aba === 'nao_lidas' ? !!l.is_unread || l.id === selecionada
    : (l.lead_tags || []).some((lt: any) => lt.tag_id === aba))
  const aberta = todas.find((l) => l.id === selecionada) || null

  const abrir = (l: LeadWithOwner) => {
    setSelecionada(l.id)
    if (l.is_unread) {
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, is_unread: false } : x)))
      fetch(`/api/leads/${l.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_unread: false }) }).catch(() => {})
    }
  }
  const aoEnviar = (conteudo: string) => {
    if (!aberta) return
    setLeads((p) => p.map((x) => (x.id === aberta.id
      ? { ...x, last_message_content: conteudo, last_message_sender_type: 'human' as const, last_activity_at: new Date().toISOString() } : x)))
  }
  const aoMudarEtiqueta = (leadId: string, tagId: string, acao: 'add' | 'remove', tag?: any) => {
    setLeads((p) => p.map((x) => x.id !== leadId ? x : {
      ...x, lead_tags: acao === 'add'
        ? [...(x.lead_tags || []), { tag_id: tagId, tag } as any]
        : (x.lead_tags || []).filter((lt: any) => lt.tag_id !== tagId),
    }))
  }

  if (loading) return <div className="flex h-full items-center justify-center"><CircleNotch size={24} className="animate-spin" /></div>
  if (!ehAdmin) return <NotAuthorized />

  const chip = (chave: string, rotulo: string, n?: number, cor?: string) => (
    <button key={chave} type="button" onClick={() => setAba(chave)}
            className="px-3 h-8 rounded-full text-[13px] font-medium flex items-center gap-1.5 flex-shrink-0"
            style={aba === chave ? { background: 'var(--wa-green)', color: '#fff' } : { background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
      {cor && <span className="w-2 h-2 rounded-full" style={{ background: cor }} />}
      {rotulo}{n !== undefined ? <span className="opacity-70">{n}</span> : null}
    </button>
  )

  return (
    <div className="chat-theme flex h-full min-h-0">
      <div className="flex flex-col min-h-0 border-r" style={{ width: 400, borderColor: 'var(--wa-divider)', background: 'var(--wa-panel)' }}>
        <div className="px-4 pt-3 pb-2 flex items-center gap-2" style={{ color: 'var(--wa-text)' }}>
          <FolderSimpleUser size={22} weight="duotone" />
          <div className="flex-1">
            <div className="text-[17px] font-semibold leading-tight">Administração</div>
            <div className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Leads e Parceria · a resposta sai pelo número de cada conversa</div>
          </div>
        </div>
        <div className="px-3 pb-2 flex gap-1.5 overflow-x-auto items-center">
          {chip('todos', 'Todos', todas.length)}
          {chip('nao_lidas', 'Não lidos', todas.filter((l) => l.is_unread).length)}
          {abas.map((id) => {
            const t = etiquetas.find((x) => x.id === id)
            return t ? chip(id, t.name, contagem(id), t.color) : null
          })}
          <button type="button" title="Escolher as etiquetas desta tela" onClick={() => setEscolhendo((v) => !v)}
                  className="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0" style={{ background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
            {escolhendo ? <X size={14} /> : <Plus size={14} />}
          </button>
        </div>
        {escolhendo && (
          <div className="mx-3 mb-2 p-2 rounded-lg flex flex-col gap-1 max-h-64 overflow-y-auto" style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
            <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>As etiquetas que viram aba aqui (a contagem é só de quem está em Administração)</span>
            {etiquetas.filter((t) => !ehEtapaComoTag(t.name) && t.id !== idFechamento).map((t) => (
              <label key={t.id} className="flex items-center gap-2 text-[13px] cursor-pointer">
                <input type="checkbox" checked={abas.includes(t.id)}
                       onChange={(e) => salvarAbas(e.target.checked ? [...abas, t.id] : abas.filter((x) => x !== t.id))} />
                <span className="w-2.5 h-2.5 rounded-full" style={{ background: t.color }} />
                <span className="flex-1">{t.name}</span>
                <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>{contagem(t.id)}</span>
              </label>
            ))}
            <button type="button" className="text-[12px] self-start mt-1" style={{ color: 'var(--wa-text-2)' }}
                    onClick={async () => {
                      const nome = window.prompt('Nome da nova etiqueta:')
                      if (!nome?.trim()) return
                      try { const t = await criarEtiqueta(nome, CORES_DE_ETIQUETA[6]); salvarAbas([...abas, t.id]) }
                      catch (e: any) { window.alert(e?.message || 'Não consegui criar a etiqueta.') }
                    }}>
              + Nova etiqueta…
            </button>
          </div>
        )}
        <div className="flex-1 min-h-0 overflow-y-auto">
          {visiveis.length === 0 && (
            <p className="px-4 py-6 text-[13px] text-center" style={{ color: 'var(--wa-text-2)' }}>Ninguém em Administração aqui.</p>
          )}
          {visiveis.map((l) => (
            <LeadListItem key={l.id} lead={l} isSelected={l.id === selecionada} timeStr={hora(l.last_activity_at || l.created_at)}
                          onClick={abrir} onContextMenu={(e, lead) => { e.preventDefault(); setMenu({ x: e.clientX, y: e.clientY, lead }) }}
                          faixaDaLinha={NUMERO[getLinhaWhatsapp(l) || ''] || null}
                          tipoDoContato={acharTipo(tipos, tipoEscolhido(l))} cinzas />
          ))}
        </div>
      </div>
      {menu && (
        <div className="fixed z-50 py-1 rounded-lg shadow-lg text-[14px] min-w-[220px]"
             style={{ left: Math.min(menu.x, window.innerWidth - 240), top: Math.min(menu.y, window.innerHeight - 170),
                      background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}
             onClick={(e) => e.stopPropagation()} onContextMenu={(e) => e.preventDefault()}>
          <div className="px-3 py-1.5 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
            Tirar da Administração e voltar para
          </div>
          {VOLTAS.map((v) => (
            <button key={v.chave} type="button" disabled={!!tirando}
                    className="w-full text-left px-3 py-2 hover:bg-black/5 dark:hover:bg-white/10 disabled:opacity-50"
                    title={`A conversa sai daqui e volta para ${v.rotulo} no número ${getLinhaWhatsapp(menu.lead) === 'parceria' ? 'Parceria' : 'Leads'}`}
                    onClick={() => tirar(menu.lead, v.chave)}>
              {v.rotulo}
            </button>
          ))}
        </div>
      )}
      {tirando && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 px-3 py-2 rounded-lg shadow text-[13px] flex items-center gap-2"
             style={{ background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>
          <CircleNotch size={14} className="animate-spin" /> Tirando da Administração…
        </div>
      )}
      <div className="flex-1 min-w-0 min-h-0">
        {aberta ? (
          <ChatWindow key={aberta.id} lead={aberta} organizationId={organizationId || ''} onMessageSent={aoEnviar}
                      linha={getLinhaWhatsapp(aberta) || undefined} marca={getLinhaWhatsapp(aberta) === 'parceria' ? marcas[aberta.id] : undefined}
                      faixaDaLinha={NUMERO[getLinhaWhatsapp(aberta) || ''] || null} onTagsChange={aoMudarEtiqueta} />
        ) : (
          <div className="wa-papel flex h-full items-center justify-center text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
            Escolha uma conversa de Administração.
          </div>
        )}
      </div>
    </div>
  )
}
