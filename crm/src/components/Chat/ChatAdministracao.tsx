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
 * 03/11, noite (Pedro: "cópias do visual do chat Leads ... e a lupinha de pesquisar"): a tela é a ChatJuntado.
 *
 * O BOTÃO DIREITO (Pedro, 03/11: "uma opção de tirar o lead quando eu clicar com o botão direito e voltar ele ao contato
 * como Todos, ou Proprietário, ou Fechamento"): o tipo Administração sai e a conversa volta às abas do número dela --
 *   Todos         sem tipo escolhido (vale o que a lista deduz); na Parceria, a etapa Todos do card
 *   Proprietário  o tipo Proprietário; na Parceria, a etapa Proprietários do card
 *   Fechamento    no Leads, a etiqueta Fechamento (que move o card para a etapa fechamento); na Parceria, a etapa do card
 * Na Parceria vai pela rota do card (/api/leads/[id]/contato), que também avisa a Nay, como quem escolhe no card.
 */
import { useCallback, useState } from 'react'
import { CircleNotch } from '@phosphor-icons/react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useTiposDeContato } from '@/hooks/useTiposDeContato'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { acharTipo, tipoEscolhido } from '@/lib/organizacaoDoLead'
import { useEtiquetas } from '@/lib/etiquetas'
import ChatJuntado from './ChatJuntado'
import { organizar } from './OrganizarConversa'

type Volta = 'todos' | 'proprietarios' | 'fechamento'
const VOLTAS: { chave: Volta; rotulo: string }[] = [
  { chave: 'todos', rotulo: 'Todos' }, { chave: 'proprietarios', rotulo: 'Proprietário' }, { chave: 'fechamento', rotulo: 'Fechamento' },
]

export default function ChatAdministracao() {
  const { setLeads } = useLeadsContext()
  const { tipos } = useTiposDeContato()
  const etiquetas = useEtiquetas()
  const idFechamento = etiquetas.find((t) => (t.nomeOriginal || t.name) === 'Fechamento')?.id
  const [tirando, setTirando] = useState('')

  const daAdministracao = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    return (linha === 'captacao' || linha === 'parceria') && acharTipo(tipos, tipoEscolhido(l))?.chave === 'administracao'
  }, [tipos])

  /** tira da Administração e devolve a conversa às abas do número dela (ver o cabeçalho) */
  const tirar = async (l: LeadWithOwner, volta: Volta) => {
    setTirando(l.id)
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
    } catch (e: any) {
      window.alert(e?.message || 'Não consegui tirar da Administração.')
    } finally { setTirando('') }
  }

  return (
    <>
      <ChatJuntado titulo="Administração" subtitulo="Leads e Parceria · a resposta sai pelo número de cada conversa"
                   pertence={daAdministracao} soAdmin chaveAbas="crm:abas-administracao" vazio="Ninguém em Administração aqui."
                   menu={(lead, fechar) => (
                     <>
                       <div className="px-4 py-1.5 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Tirar da Administração e voltar para</div>
                       {VOLTAS.map((v) => (
                         <button key={v.chave} type="button" disabled={!!tirando}
                                 className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] disabled:opacity-50"
                                 title={`A conversa sai daqui e volta para ${v.rotulo} no número ${getLinhaWhatsapp(lead) === 'parceria' ? 'Parceria' : 'Leads'}`}
                                 onClick={() => { fechar(); void tirar(lead, v.chave) }}>
                           {v.rotulo}
                         </button>
                       ))}
                     </>
                   )} />
      {tirando && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-50 px-3 py-2 rounded-lg shadow text-[13px] flex items-center gap-2"
             style={{ background: 'var(--wa-panel, #fff)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}>
          <CircleNotch size={14} className="animate-spin" /> Tirando da Administração…
        </div>
      )}
    </>
  )
}
