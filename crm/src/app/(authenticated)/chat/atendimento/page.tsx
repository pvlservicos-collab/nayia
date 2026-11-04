'use client'

/*
 * ATENDIMENTO (v2 do CRM, Pedro, 03/11/2026: "uma aba que tem os 2 WhatsApp para selecionar lá em cima"). É a mesma tela
 * de cada número (ChatWhatsApp), sem os proprietários (eles ficam na aba Proprietários). No Leads, a locação é do Diego:
 * ele só vê a locação; quem vê o resto tem o botão "Mandar para locação" no alto da conversa. Ver lib/versaoDoCrm.ts.
 */
import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { acessoV2, type LinhaDoAtendimento } from '@/lib/versaoDoCrm'
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'
import { organizar } from '@/components/Chat/OrganizarConversa'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import type { LeadWithOwner } from '@/lib/types'

const CHAVE = 'crm:v2:linha-do-atendimento'
const ROTULO: Record<LinhaDoAtendimento, string> = { captacao: 'WhatsApp Leads · 8595', parceria: 'WhatsApp Parceria · 9445' }

function BotaoLocacao({ lead, ehLocacao }: { lead: LeadWithOwner; ehLocacao: boolean }) {
  const { setLeads } = useLeadsContext()
  const [ocupado, setOcupado] = useState(false)
  const trocar = async () => {
    setOcupado(true)
    try {
      const o = await organizar(lead.id, { locacao: !ehLocacao })
      setLeads((p) => p.map((x) => (x.id === lead.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
    } catch (e: any) { window.alert(e?.message || 'Não consegui mudar.') } finally { setOcupado(false) }
  }
  return (
    <button type="button" onClick={trocar} disabled={ocupado}
            title={ehLocacao ? 'Tira da locação: volta para o atendimento de vendas' : 'Manda este lead para a locação (Diego)'}
            className="flex items-center gap-1.5 h-9 px-3 rounded-lg text-[13px] font-semibold flex-shrink-0 disabled:opacity-60"
            style={ehLocacao ? { background: 'var(--wa-search)', color: 'var(--wa-text)' } : { background: '#0891b2', color: '#fff' }}>
      {ehLocacao ? 'Na locação · tirar' : 'Mandar para locação'}
    </button>
  )
}

export default function AtendimentoPage() {
  const { isMaster, roleName, permissions, profileName, user, loading } = useAuth()
  const admin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const acesso = acessoV2(admin, profileName || user?.name)
  const { ehProprietario, ehLocacao } = usePapelDoContato()
  // 04/11 (Pedro): o lead em fechamento é só do Tel e de quem ele incluir (hooks/useFechamentoV2.ts)
  const { podeVer } = useFechamentoV2()
  const [linha, setLinha] = useState<LinhaDoAtendimento | null>(null)

  useEffect(() => {
    if (loading) return
    let guardada: string | null = null
    try { guardada = localStorage.getItem(CHAVE) } catch {}
    setLinha(acesso.linhas.includes(guardada as any) ? (guardada as LinhaDoAtendimento) : acesso.linhas[0] || null)
  }, [loading, acesso.linhas.join()])
  const escolher = (l: LinhaDoAtendimento) => { setLinha(l); try { localStorage.setItem(CHAVE, l) } catch {} }

  if (loading) return null
  if (!acesso.linhas.length) return <NotAuthorized />
  if (!linha) return null

  const filtro = (l: LeadWithOwner) => !ehProprietario(l) && podeVer(l) && (linha !== 'captacao' || !acesso.soLocacao || ehLocacao(l))
  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      <div className="flex items-center gap-2 px-4 py-2 flex-shrink-0" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <span className="text-[15px] font-semibold mr-2" style={{ color: 'var(--wa-text)' }}>Atendimento</span>
        {acesso.linhas.map((l) => (
          <button key={l} type="button" onClick={() => escolher(l)} aria-pressed={linha === l}
                  className="px-3 h-8 rounded-full text-[13px] font-medium"
                  style={linha === l ? { background: 'var(--wa-green)', color: '#fff' } : { background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
            {ROTULO[l]}{l === 'captacao' && acesso.soLocacao ? ' · locação' : ''}
          </button>
        ))}
        <span className="ml-auto text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Os proprietários ficam na aba Proprietários</span>
      </div>
      <div className="flex-1 min-h-0">
        <ChatWhatsApp key={linha} linha={linha} filtro={filtro}
                      extraNoTopo={linha === 'captacao' && !acesso.soLocacao ? (l) => <BotaoLocacao lead={l} ehLocacao={ehLocacao(l)} /> : undefined} />
      </div>
    </div>
  )
}
