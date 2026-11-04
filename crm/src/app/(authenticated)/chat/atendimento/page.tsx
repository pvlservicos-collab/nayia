'use client'

/*
 * ATENDIMENTO (v2 do CRM, Pedro, 03/11/2026: "uma aba que tem os 2 WhatsApp para selecionar lá em cima"). É a mesma tela
 * de cada número (ChatWhatsApp), sem os proprietários (eles ficam na aba Proprietários). No Leads, a locação é do Diego:
 * ele só vê a locação; quem vê o resto tem o botão "Enviar para Diego" no alto da conversa (OrganizarConversa). Ver lib/versaoDoCrm.ts.
 */
import { useEffect, useState } from 'react'
import { useAuth } from '@/hooks'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { acessoV2, usePapelV2, type LinhaDoAtendimento } from '@/lib/versaoDoCrm'
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import type { LeadWithOwner } from '@/lib/types'

const CHAVE = 'crm:v2:linha-do-atendimento'
const ROTULO: Record<LinhaDoAtendimento, string> = { captacao: 'WhatsApp Leads · 8595', parceria: 'WhatsApp Parceria · 9445' }

export default function AtendimentoPage() {
  const { loading } = useAuth()
  // 04/11: o Visualizar por do administrador vale aqui (usePapelV2)
  const papel = usePapelV2()
  const acesso = acessoV2(papel.admin, papel.nome, papel.abas)
  const [linha, setLinha] = useState<LinhaDoAtendimento | null>(null)
  // 04/11: quem só usa a Parceria (a Rayssa) só carrega as leituras do Leads com o Leads aberto
  const { ehProprietario, ehLocacao } = usePapelDoContato(true, !acesso.soOsNumerosDela || linha === 'captacao')
  // 04/11 (Pedro): o lead em fechamento é só do Tel e de quem ele incluir (hooks/useFechamentoV2.ts)
  const { podeVer } = useFechamentoV2()

  useEffect(() => {
    if (loading) return
    let guardada: string | null = null
    // 04/11: a Rayssa sempre abre na Parceria (a primeira); o Leads só quando ela clica
    try { guardada = acesso.soOsNumerosDela ? null : localStorage.getItem(CHAVE) } catch {}
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
        {/* 04/11: o "Mandar para locação" daqui virou o "Enviar para Diego" do alto da conversa (OrganizarConversa) */}
        <ChatWhatsApp key={linha} linha={linha} filtro={filtro} />
      </div>
    </div>
  )
}
