'use client'

/**
 * A V3 DO CRM (Pedro, 04/11/2026): "quero testar uma nova versão do CRM, parecida com a v2, só no cadastro Tel ... um número
 * de WhatsApp só juntando Leads e Parceria ... o lead é atendido, depois que confirma que quer uma visita vai para a aba
 * Visita ... nesse número vamos falar com corretores e leads ... as tags: Em atendimento, Leads, Corretores, Visitas,
 * Fechamento, Proprietários". E, depois de ver a primeira versão: "cadê as etapas que eu pedi no chat da v3? tá tudo
 * bagunçado, eu pedi as tags específicas": UMA lista só (a cara do WhatsApp Leads), e as seis etapas são os chips do alto
 * dela, e só elas. O Captação e o WhatsApp Oficial continuam à parte (são outros propósitos).
 *
 * É só a TELA: cada conversa continua sendo da linha dela (crm/CLAUDE.md, um lead por pessoa em cada linha), e a resposta sai
 * pelo número dela. A Nay que atende segue a origem, como já é: quem veio do Leads (OLX e os outros canais) é a Nay Leads;
 * quem veio da Parceria é a Nay Parceria. Nada mudou no servidor.
 *
 * A conversa está em UMA etapa só, na ordem do funil (a mais adiante vence): Fechamento > Proprietários > Visitas >
 * Em atendimento > Corretores > Leads. O mesmo telefone nos dois números aparece uma vez só, pela Parceria (a regra da v2).
 *
 *   Em atendimento  a etapa "Em atendimento" do funil (a que o CRM põe quando alguém responde) -- dos dois números
 *   Corretores      tudo o que fala pela Parceria e os corretores do número Leads
 *   Leads           o resto do número Leads (OLX e os outros canais)
 *   Visitas         quem está na etapa visita (Parceria: etapa Visitas; Leads: a etiqueta Visita)
 *   Fechamento      só o Tel e quem ele incluiu (a mesma regra da v2)
 *   Proprietários   os donos dos dois números
 * (Pedro: "testa aí, mas eu vou mudar": as regras ficam todas em `etapaDe`.)
 */
import { useCallback, useMemo } from 'react'
import { useAuth } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { useCorretoresDaCaptacao } from '@/hooks/useCorretoresDaCaptacao'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import { primeiroNome, usePapelV2 } from '@/lib/versaoDoCrm'
import type { LeadWithOwner } from '@/lib/types'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import ChatJuntado from './ChatJuntado'

type EtapaV3 = 'atendimento' | 'leads' | 'corretores' | 'visitas' | 'fechamento' | 'proprietarios'
const ETAPAS: Array<{ chave: EtapaV3; rotulo: string }> = [
  { chave: 'atendimento', rotulo: 'Em atendimento' }, { chave: 'leads', rotulo: 'Leads' }, { chave: 'corretores', rotulo: 'Corretores' },
  { chave: 'visitas', rotulo: 'Visitas' }, { chave: 'fechamento', rotulo: 'Fechamento' }, { chave: 'proprietarios', rotulo: 'Proprietários' },
]

/** o login Tel (administrador de verdade): a v3 é só dele, por enquanto */
export function useEhTel(): boolean {
  const { profileName, user } = useAuth()
  const papel = usePapelV2()
  return papel.adminDeVerdade && primeiroNome(profileName || user?.name) === 'tel'
}

const emAtendimento = (l: LeadWithOwner) => /atendimento/i.test(String((l as any).stage?.name || ''))

export default function ChatV3() {
  const { loading } = useAuth()
  const ehTel = useEhTel()
  const { leads } = useLeadsContext()
  const { ehProprietario, ehVisita } = usePapelDoContato(true, true)
  const { emFechamento, podeVer } = useFechamentoV2()
  const corretoresDoLeads = useCorretoresDaCaptacao(true)

  // o telefone que já tem conversa na Parceria: o do Leads some (vale a Parceria)
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria').map((l) => fim8(l.phone)).filter(Boolean)), [leads])

  /** em qual etapa a conversa está (ou null: é de outro número, grupo ou o Tel não a liberou) */
  const etapaDe = useCallback((l: LeadWithOwner): EtapaV3 | null => {
    const linha = getLinhaWhatsapp(l)
    if (l.is_group || (linha !== 'captacao' && linha !== 'parceria')) return null
    if (linha === 'captacao' && pelaParceria.has(fim8(l.phone))) return null
    if (!podeVer(l)) return null
    if (emFechamento(l)) return 'fechamento'
    if (ehProprietario(l)) return 'proprietarios'
    if (ehVisita(l)) return 'visitas'
    if (emAtendimento(l)) return 'atendimento'
    if (linha === 'parceria' || corretoresDoLeads.has(fim8(l.phone))) return 'corretores'
    return 'leads'
  }, [pelaParceria, emFechamento, ehProprietario, ehVisita, podeVer, corretoresDoLeads])

  const etapas = useMemo(() => ETAPAS.map((e) => ({ ...e, casa: (l: LeadWithOwner) => etapaDe(l) === e.chave })), [etapaDe])

  if (loading) return null
  if (!ehTel) return <NotAuthorized />

  return (
    <div className="chat-theme h-full min-h-0">
      <ChatJuntado titulo="WhatsApp · v3" subtitulo="Leads e Parceria num lugar só · a resposta sai pelo número de cada conversa"
                   pertence={(l) => etapaDe(l) !== null} etapas={etapas} chaveAbas="crm:abas-v3"
                   vazio="Nenhuma conversa nesta etapa." />
    </div>
  )
}
