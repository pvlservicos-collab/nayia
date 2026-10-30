'use client'

/**
 * A ETAPA NO CARD DA CAPTAÇÃO (Pedro, 01/10/2026): "adicione lá na aba captação
 * a mesma ferramenta de mudar a etapa do lead que nem na parceria, mas com as
 * etapas da captação, e adicione lá mais uma etapa: follow-up".
 *
 * Mesmo desenho do EtapaDoLead da Parceria: escolher só acende o Salvar; nada
 * sai daqui até clicar. "Todos" solta e devolve a etapa à campanha; "Com o Tel"
 * cala a Nay para essa pessoa até voltar para Todos (migração 242).
 */
import { useCallback, useEffect, useState } from 'react'
import AvisoFlutuante, { type AvisoNaTela } from './AvisoFlutuante'

export const ETAPAS_DA_CAPTACAO: Array<{ chave: string; rotulo: string; titulo: string; pessoa?: boolean }> = [
  { chave: 'todos', rotulo: 'Todos', titulo: 'Solta: a etapa volta a ser a que a campanha diz' },
  { chave: 'em_andamento', rotulo: 'Em andamento', titulo: 'Respondeu e a conversa ainda não fechou' },
  { chave: 'followup', rotulo: 'Follow-up', titulo: 'Para voltar a falar com essa pessoa' },
  { chave: 'sem_resposta', rotulo: 'Sem resposta', titulo: 'Recebeu a mensagem e não respondeu' },
  { chave: 'disponiveis', rotulo: 'Disponíveis', titulo: 'O imóvel dele está disponível' },
  { chave: 'alugados', rotulo: 'Alugados', titulo: 'O imóvel dele está alugado' },
  { chave: 'quer_vender', rotulo: 'Quer vender', titulo: 'Ele quer vender' },
  { chave: 'ja_vendeu', rotulo: 'Já vendeu', titulo: 'Ele já vendeu' },
  { chave: 'tem_outro_imovel', rotulo: 'Tem outro imóvel', titulo: 'Ele falou de outro imóvel' },
  { chave: 'com_o_tel', rotulo: 'Com o Tel', titulo: 'A Nay para de responder essa pessoa', pessoa: true },
  // 501 (Pedro, 26/10): aba Rayssa do lado do Tel na captação -- mesmo efeito do Com o Tel (a Nay cala)
  { chave: 'rayssa', rotulo: 'Rayssa', titulo: 'A Rayssa está com essa conversa; a Nay para de responder', pessoa: true },
  // 534 (Pedro, 30/10: "troca a tag Rayssa lá no Leads pela tag Lucas, ele vai ficar responsável pelo atendimento no
  // Leads"): no Leads o botão é o do Lucas; a Oficial continua com o da Rayssa
  { chave: 'lucas', rotulo: 'Lucas', titulo: 'O Lucas está com essa conversa; a Nay para de responder', pessoa: true },
]

export const ROTULO_DA_ETAPA_DA_CAPTACAO: Record<string, string> =
  Object.fromEntries(ETAPAS_DA_CAPTACAO.map((e) => [e.chave, e.rotulo]))

export default function EtapaDaCaptacao({ leadId, etapaManual, abas, aoMudar, oficial = false }: {
  leadId: string
  /** a conversa é da linha Oficial (lá o botão de pessoa ainda é o da Rayssa; no Leads, o do Lucas) */
  oficial?: boolean
  /** a etapa escolhida à mão, quando alguém escolheu (242) */
  etapaManual: string | null
  /** as abas que a campanha deduziu, quando ninguém escolheu (236) */
  abas: string[]
  aoMudar?: (etapa: string) => void
}) {
  /* onde ele está hoje: a escolha da mão manda; senão, a primeira aba da campanha */
  const ondeEsta = etapaManual || abas[0] || 'todos'
  const [escolhido, setEscolhido] = useState(ondeEsta)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [recado, setRecado] = useState<string | null>(null)
  /* A NOTIFICAÇÃO (Pedro, 03/10/2026: "coloca um aviso claro quando eu mudar o status de
     um contato... põe uma notificaçãozinha"). O recado do Salvar existia, mas este efeito
     o apagava no mesmo instante: salvar muda `ondeEsta`, e o efeito limpava tudo. Agora o
     recado só sai ao trocar de conversa ou ao escolher outra etapa, e sobe no pé da tela. */
  const [aviso, setAviso] = useState<AvisoNaTela | null>(null)
  const fecharAviso = useCallback(() => setAviso(null), [])
  useEffect(() => { setEscolhido(ondeEsta); setErro(null) }, [leadId, ondeEsta])
  useEffect(() => { setRecado(null) }, [leadId])
  const mudou = escolhido !== ondeEsta

  async function salvar() {
    if (salvando || !mudou) return
    setSalvando(true); setErro(null); setRecado(null)
    try {
      const r = await fetch(`/api/leads/${leadId}/captacao-etapa`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ etapa: escolhido }),
      })
      const j = await r.json().catch(() => ({} as any))
      if (!r.ok || j?.ok === false) throw new Error(j?.mensagem || j?.error || 'o servidor não aceitou a mudança')
      const texto = String(j?.mensagem || 'Pronto.')
      setRecado(texto)
      setAviso({ tom: 'ok', titulo: `Salvo: ${ROTULO_DA_ETAPA_DA_CAPTACAO[escolhido] || escolhido}`, texto })
      aoMudar?.(escolhido)
    } catch (e: any) {
      const texto = e?.message || 'não salvou'
      setErro(texto)
      setAviso({ tom: 'erro', titulo: `Não salvou: ${ROTULO_DA_ETAPA_DA_CAPTACAO[escolhido] || escolhido}`, texto: `${texto}. Nada mudou; tente de novo.` })
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="px-4 py-3 border-b border-[var(--chat-border)]">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-secondary)] mb-2">Etapa da captação</p>
      <div className="flex flex-wrap items-center gap-1.5">
        {ETAPAS_DA_CAPTACAO.filter((e) => e.chave !== (oficial ? 'lucas' : 'rayssa') || ondeEsta === e.chave).map((e) => (
          <span key={e.chave} className="contents">
            {/* o risco só separa etapa de pessoa uma vez (antes do Tel, o primeiro dos dois) */}
            {e.chave === 'com_o_tel' && <span className="wa-fase__risco" aria-hidden="true" />}
            <button type="button" onClick={() => { setEscolhido(e.chave); setRecado(null) }} disabled={salvando} title={e.titulo}
                    className={`wa-fase wa-fase--${e.pessoa ? 'pessoa' : 'etapa'}`
                      + `${e.chave !== 'todos' && !e.pessoa ? ' wa-fase--rosa' : ''}`
                      + `${escolhido === e.chave ? ' wa-fase--on' : ''}`}>
              {e.rotulo}
            </button>
          </span>
        ))}
      </div>
      <div className="mt-2 flex items-center gap-2">
        <button type="button" onClick={salvar} disabled={!mudou || salvando} className="wa-botao-principal">
          {salvando ? 'Salvando…' : 'Salvar'}
        </button>
        {mudou && !salvando && (
          <span className="text-[11px] text-[var(--chat-text-secondary)]">
            vai para {ROTULO_DA_ETAPA_DA_CAPTACAO[escolhido]} ao salvar
          </span>
        )}
      </div>
      {(erro || recado) && (
        <p className={`mt-2 text-[11.5px] leading-4 ${erro ? 'text-red-500' : 'text-emerald-500'}`}>{erro || recado}</p>
      )}
      <AvisoFlutuante aviso={aviso} aoFechar={fecharAviso} />
      {!erro && !recado && (
        <p className="mt-2 text-[11px] text-[var(--chat-text-secondary)]">
          {etapaManual
            ? 'Preso aqui por você. Escolha Todos e salve para devolver a etapa à campanha.'
            : 'A etapa está saindo do que a campanha gravou nesta conversa.'}
        </p>
      )}
    </div>
  )
}
