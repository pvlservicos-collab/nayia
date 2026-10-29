'use client'

/**
 * A ETAPA NO CARD DO LEAD (Tel, 30/09/2026): "preciso que dê para mudar lá no
 * card do cliente a etapa dele, tenho um menu igual tem na conversa para eu
 * editar lá pelo card do lead".
 *
 * Mesmos quatro botões do menu da lista, com o mesmo relevo -- é para ser a
 * mesma coisa, no lugar onde ele está olhando a pessoa.
 *
 * A etapa é o FATO que a Nay sabe (visita passada à equipe, é dono, pediu o
 * checklist), e ele manda sempre -- escolher aqui NÃO prende (Pedro, 01/10:
 * "não quero isso de escolha à mão ganhar de nada, isso tudo é um estado
 * temporário"). A escolha só vale quando a Nay não sabe de nada, e por 7 dias
 * (Visitas não vence desde a 379: ninguém sai de lá sozinho).
 * "Todos" não é "mover para Todos": é soltar -- do lado da Nay ele conclui o
 * fechamento aberto e tira a marca de humano, e a conversa volta por
 * consequência.
 *
 * O AVISO DEPOIS DE SALVAR (Pedro, 03/10/2026): "coloca um aviso claro quando eu
 * mudar o status de um contato; tem uns que eu coloco para Todos e não salva; põe
 * uma notificaçãozinha". Salvava, mas a tela ficava muda -- e quando um fato da
 * Nay segura a conversa (é proprietário, tem visita confirmada...) ela nem sai do
 * lugar, e o botão continuava dizendo "vai para Todos ao salvar". Agora, depois
 * de salvar, a tela lê as marcas da Nay de novo, vê onde a conversa FICOU e diz:
 * "Movido para X", ou "Não foi para X: continua em Y", com o motivo. Sai numa
 * notificação no pé da tela e fica escrito no card. O botão aceso passou a ser a
 * aba em que a conversa aparece na lista (`abaDaConversa`), não a última escolha.
 */
import { useCallback, useEffect, useState } from 'react'
import { useParceriaMarcas, marcasDepoisDeMudar } from '@/hooks/useParceriaMarcas'
import { abaDaConversa, escolhaAMao, resultadoDaMudanca, DESTINOS_DA_PARCERIA, ROTULO_DA_ETAPA, type DestinoParceria } from '@/lib/etapaDaParceria'
import type { LeadWithOwner } from '@/lib/types'
import AvisoFlutuante, { type AvisoNaTela } from './AvisoFlutuante'

export default function EtapaDoLead({ lead, onUpdateLead, semExplicacao }: {
  lead: LeadWithOwner
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
  /** o card do contato mostra a frase lá embaixo, antes do histórico (Pedro, 30/09) */
  semExplicacao?: boolean
}) {
  const { marcas } = useParceriaMarcas(true)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  /* o que aconteceu no último Salvar: fica escrito no card e sobe na notificação */
  const [resultado, setResultado] = useState<AvisoNaTela | null>(null)
  const [aviso, setAviso] = useState<AvisoNaTela | null>(null)
  const fecharAviso = useCallback(() => setAviso(null), [])

  const m = marcas[lead.id]
  const aMao = escolhaAMao(lead as any)
  /* ONDE ELE ESTÁ HOJE: a aba em que a conversa aparece na lista -- pessoa (Tel ou
     Rayssa) na frente; depois a etapa, com o fato da Nay valendo mais que a escolha. */
  const ondeEsta: DestinoParceria = abaDaConversa(lead as any, m)

  /* O BOTÃO SALVAR (Tel, 30/09): "um botão para salvar e quando eu salvar ele
     vai automaticamente para a etapa lá nas conversas". Escolher só acende o
     botão; nada sai daqui até ele clicar em Salvar -- um clique errado no
     menu não deve mudar a conversa de lugar. */
  const [escolhido, setEscolhido] = useState<DestinoParceria>(ondeEsta)
  useEffect(() => { setEscolhido(ondeEsta); setErro(null) }, [lead.id, ondeEsta])
  // o recado do último Salvar é desta conversa: trocou de conversa, sai
  useEffect(() => { setResultado(null) }, [lead.id])
  const mudou = escolhido !== ondeEsta

  /* ONDE ELE PAROU (Pedro, 30/09): o resumo da revisão de 30/09, para quem
     abre uma conversa velha não ter que ler tudo de novo. */
  const [retomada, setRetomada] = useState<{ resumo: string | null; proximoPasso: string | null; imoveis: number[] } | null>(null)
  useEffect(() => {
    let vivo = true
    setRetomada(null)
    if (!lead.phone) return
    fetch(`/api/parceria/retomada?telefone=${encodeURIComponent(lead.phone)}`)
      .then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (vivo && d?.retomada) setRetomada(d.retomada) })
      .catch(() => {})
    return () => { vivo = false }
  }, [lead.id, lead.phone])

  async function salvar() {
    if (salvando || !mudou) return
    const etapa = escolhido
    setSalvando(true); setErro(null); setResultado(null)
    try {
      const r = await fetch(`/api/leads/${lead.id}/contato`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ etapa }),
      })
      const j = await r.json().catch(() => ({} as any))
      if (!r.ok) throw new Error(j?.error || 'o servidor não aceitou a mudança')
      // a tela não espera o próximo carregamento para mostrar a mudança
      const antes = (lead as any).custom_attributes || {}
      const depois = { ...antes }
      // 'todos' solta a conversa e devolve à Nay; o resto prende
      if (etapa === 'todos') delete depois.etapa_parceria
      else { depois.etapa_parceria = etapa; depois.etapa_parceria_em = new Date().toISOString() }
      onUpdateLead?.(lead.id, { custom_attributes: depois } as any)
      /* ONDE ELA FICOU DE VERDADE: quem sabe é a Nay. Lê as marcas de novo, sem cache;
         se a leitura falhar, vale a que já estava na tela. */
      const novas = await marcasDepoisDeMudar().catch(() => null)
      const res = resultadoDaMudanca(etapa, { custom_attributes: depois }, (novas || marcas)[lead.id], j?.nayRecebeu !== false)
      const recado: AvisoNaTela = { tom: res.tom, titulo: res.titulo, texto: res.texto }
      setResultado(recado); setAviso(recado)
      // o botão aceso é onde ela está: sem isto ficava "vai para Todos ao salvar" para sempre
      setEscolhido(res.ficou)
    } catch (e: any) {
      const texto = e?.message || 'não salvou'
      setErro(texto)
      setAviso({ tom: 'erro', titulo: `Não salvou: ${ROTULO_DA_ETAPA[etapa]}`, texto: `${texto}. Nada mudou; tente de novo.` })
    } finally {
      setSalvando(false)
    }
  }

  return (
    <div className="px-4 py-3 border-b border-[var(--chat-border)]">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-secondary)] mb-2">Etapa</p>
      <div className="flex flex-wrap items-center gap-1.5">
        {DESTINOS_DA_PARCERIA.map((d, i) => (
          <span key={d} className="contents">
            {/* o mesmo risco do menu de cima, separando etapa de pessoa */}
            {d === 'tel' && <span className="wa-fase__risco" aria-hidden="true" />}
            <button
              type="button"
              onClick={() => { setEscolhido(d); setResultado(null) }}
              disabled={salvando}
              title={d === 'todos'
                ? 'Solta a conversa: a Nay volta a decidir e a atender'
                : d === 'tel' ? 'Manda para o Tel: a Nay se cala até o DEVOLVER'
                : d === 'rayssa' ? 'Manda para a Rayssa: sai do fluxo da Nay'
                : `Prende a conversa em ${ROTULO_DA_ETAPA[d]}`}
              className={`wa-fase wa-fase--${d === 'tel' || d === 'rayssa' ? 'pessoa' : 'etapa'}`
                + `${d !== 'todos' && d !== 'tel' && d !== 'rayssa' ? ' wa-fase--rosa' : ''}`
                + `${escolhido === d ? ' wa-fase--on' : ''}`}
            >
              {ROTULO_DA_ETAPA[d]}
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
            vai para {ROTULO_DA_ETAPA[escolhido]} ao salvar
          </span>
        )}
      </div>
      {resultado && (
        <div role="status" className="mt-2 rounded-md px-2.5 py-2 text-[12px] leading-[17px]"
             style={{ border: `1px solid ${resultado.tom === 'ok' ? '#16a34a' : '#d97706'}`,
                      background: `color-mix(in srgb, ${resultado.tom === 'ok' ? '#16a34a' : '#d97706'} 12%, transparent)` }}>
          <b className="block">{resultado.titulo}</b>
          {resultado.texto}
        </div>
      )}
      <AvisoFlutuante aviso={aviso} aoFechar={fecharAviso} />
      {retomada && (retomada.resumo || retomada.proximoPasso) && (
        <div className="mt-3 rounded-md border border-[var(--chat-border)] p-2">
          <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--chat-text-secondary)]">Onde parou (revisão de 30/09)</p>
          {retomada.resumo && <p className="mt-1 text-[12px] leading-snug text-[var(--chat-text-primary)]">{retomada.resumo}</p>}
          {retomada.proximoPasso && (
            <p className="mt-1 text-[12px] leading-snug text-[var(--chat-text-primary)]">
              <span className="text-[var(--chat-text-secondary)]">Próximo passo: </span>{retomada.proximoPasso}
            </p>
          )}
          {!!retomada.imoveis?.length && (
            <p className="mt-1 text-[11px] text-[var(--chat-text-secondary)]">Imóveis: {retomada.imoveis.join(', ')}</p>
          )}
        </div>
      )}
      {(erro || !semExplicacao) && (
        <p className="mt-2 text-[11px] text-[var(--chat-text-secondary)]">
          {erro
            ? <span className="text-red-500">{erro}</span>
            : aMao
              ? 'A Nay já sabe. Se abrir visita, fechamento, ou o imóvel for dele, a conversa vai para a etapa do fato. Esta escolha vale 7 dias; Visitas fica até alguém mudar a etapa.'
              : 'A Nay está decidindo sozinha: visita passada à equipe, dono do imóvel ou checklist pedido.'}
        </p>
      )}
    </div>
  )
}
