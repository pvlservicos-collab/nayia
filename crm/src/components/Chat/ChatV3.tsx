'use client'

/**
 * A V3 DO CRM (Pedro, 04/11/2026): "quero testar uma nova versão do CRM, parecida com a v2, só no cadastro Tel ... um número
 * de WhatsApp só juntando Leads e Parceria ... o lead é atendido, depois que confirma que quer uma visita vai para a aba
 * Visita ... nesse número vamos falar com corretores e leads ... as abas: Em atendimento, Leads, Corretores, Visitas,
 * Fechamento, Proprietários". O Captação e o WhatsApp Oficial continuam à parte (são outros propósitos).
 *
 * É só a TELA: cada conversa continua sendo da linha dela (crm/CLAUDE.md, um lead por pessoa em cada linha), e a resposta sai
 * pelo número dela. A Nay que atende segue a origem, como já é: quem veio do Leads (OLX e os outros canais) é a Nay Leads;
 * quem veio da Parceria é a Nay Parceria. Nada mudou no servidor.
 *
 * A conversa está em UMA aba só, na ordem do funil (a mais adiante vence): Fechamento > Proprietários > Visitas >
 * Em atendimento > Corretores > Leads. O mesmo telefone nos dois números aparece uma vez só, pela Parceria (a mesma regra
 * da v2). Visitas, Fechamento e Proprietários são as telas da v2 (ChatPorEtapa), sem mudança.
 *
 *   Em atendimento  a etapa "Em atendimento" do funil (a que o CRM põe quando alguém responde) -- dos dois números
 *   Corretores      tudo o que fala pela Parceria e os corretores do número Leads
 *   Leads           o resto do número Leads (OLX e os outros canais)
 * (Pedro: "testa aí, mas eu vou mudar": as regras de Em atendimento / Corretores / Leads ficam todas em `abaDe`.)
 */
import { useCallback, useMemo, useState } from 'react'
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
import ChatPorEtapa from './ChatPorEtapa'

type AbaV3 = 'atendimento' | 'leads' | 'corretores' | 'visitas' | 'fechamento' | 'proprietarios'
const ABAS: Array<{ chave: AbaV3; rotulo: string }> = [
  { chave: 'atendimento', rotulo: 'Em atendimento' }, { chave: 'leads', rotulo: 'Leads' }, { chave: 'corretores', rotulo: 'Corretores' },
  { chave: 'visitas', rotulo: 'Visitas' }, { chave: 'fechamento', rotulo: 'Fechamento' }, { chave: 'proprietarios', rotulo: 'Proprietários' },
]
const CHAVE = 'crm:v3:aba'
const SUBTITULO: Record<'atendimento' | 'leads' | 'corretores', string> = {
  atendimento: 'Quem está sendo atendido agora, dos dois números · a resposta sai pelo número de cada conversa',
  leads: 'Quem chegou pelo número Leads (OLX e outros canais) · atende a Nay Leads',
  corretores: 'Os corretores: Parceria e os do número Leads · na Parceria atende a Nay Parceria',
}

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
  const [aba, setAba] = useState<AbaV3>(() => {
    try { const g = localStorage.getItem(CHAVE) as AbaV3 | null; if (g && ABAS.some((a) => a.chave === g)) return g } catch {}
    return 'atendimento'
  })
  const escolher = (a: AbaV3) => { setAba(a); try { localStorage.setItem(CHAVE, a) } catch {} }

  // o telefone que já tem conversa na Parceria: o do Leads some (vale a Parceria)
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria').map((l) => fim8(l.phone)).filter(Boolean)), [leads])

  /** em qual das três abas de conversa a conversa cai (ou null: é de outra aba, de outro número ou grupo) */
  const abaDe = useCallback((l: LeadWithOwner): 'atendimento' | 'leads' | 'corretores' | null => {
    const linha = getLinhaWhatsapp(l)
    if (l.is_group || (linha !== 'captacao' && linha !== 'parceria')) return null
    if (linha === 'captacao' && pelaParceria.has(fim8(l.phone))) return null
    if (emFechamento(l) || ehProprietario(l) || ehVisita(l)) return null   // essas têm aba própria
    if (!podeVer(l)) return null
    if (emAtendimento(l)) return 'atendimento'
    if (linha === 'parceria' || corretoresDoLeads.has(fim8(l.phone))) return 'corretores'
    return 'leads'
  }, [pelaParceria, emFechamento, ehProprietario, ehVisita, podeVer, corretoresDoLeads])

  const contagem = useMemo(() => {
    const c = { atendimento: 0, leads: 0, corretores: 0 }
    for (const l of leads) { const a = abaDe(l); if (a) c[a]++ }
    return c
  }, [leads, abaDe])

  if (loading) return null
  if (!ehTel) return <NotAuthorized />

  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      <div className="flex items-center gap-2 px-4 py-2 flex-shrink-0 overflow-x-auto" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <span className="text-[15px] font-semibold mr-2 flex-shrink-0" style={{ color: 'var(--wa-text)' }}>v3 · WhatsApp</span>
        {ABAS.map((a) => (
          <button key={a.chave} type="button" onClick={() => escolher(a.chave)} aria-pressed={aba === a.chave}
                  className="px-3 h-8 rounded-full text-[13px] font-medium flex-shrink-0"
                  style={aba === a.chave ? { background: 'var(--wa-green)', color: '#fff' } : { background: 'var(--wa-search)', color: 'var(--wa-text)' }}>
            {a.rotulo}{a.chave in contagem ? ` · ${contagem[a.chave as keyof typeof contagem]}` : ''}
          </button>
        ))}
        <span className="ml-auto text-[12px] flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>Teste: só o login Tel vê</span>
      </div>
      <div className="flex-1 min-h-0">
        {aba === 'visitas' ? <ChatPorEtapa etapa="visita" />
          : aba === 'fechamento' ? <ChatPorEtapa etapa="fechamento" />
          : aba === 'proprietarios' ? <ChatPorEtapa etapa="proprietarios" />
          : (
            <ChatJuntado key={aba} titulo={ABAS.find((x) => x.chave === aba)!.rotulo} subtitulo={SUBTITULO[aba]}
                         pertence={(l) => abaDe(l) === aba} chaveAbas={`crm:abas-v3-${aba}`}
                         vazio={aba === 'atendimento' ? 'Ninguém em atendimento agora.' : aba === 'leads' ? 'Nenhum lead agora.' : 'Nenhum corretor agora.'} />
          )}
      </div>
    </div>
  )
}
