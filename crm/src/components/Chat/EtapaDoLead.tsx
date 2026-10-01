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
 * temporário"). A escolha só vale quando a Nay não sabe de nada, e por 7 dias.
 * "Todos" não é "mover para Todos": é soltar -- do lado da Nay ele conclui o
 * fechamento aberto e tira a marca de humano, e a conversa volta por
 * consequência.
 */
import { useEffect, useState } from 'react'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { etapaDaParceria, escolhaAMao, DESTINOS_DA_PARCERIA, ROTULO_DA_ETAPA, type DestinoParceria } from '@/lib/etapaDaParceria'
import type { LeadWithOwner } from '@/lib/types'

export default function EtapaDoLead({ lead, onUpdateLead, semExplicacao }: {
  lead: LeadWithOwner
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
  /** o card do contato mostra a frase lá embaixo, antes do histórico (Pedro, 30/09) */
  semExplicacao?: boolean
}) {
  const { marcas } = useParceriaMarcas(true)
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [salvo, setSalvo] = useState(false)

  const m = marcas[lead.id]
  const aMao = escolhaAMao(lead as any)
  const comOTel = m?.telAtendendo === true && !(m?.telMotivo || '').startsWith('Rayssa:')
  const comARayssa = (m?.telMotivo || '').startsWith('Rayssa:')
  /* ONDE ELE ESTÁ HOJE: a escolha da mão manda; senão, o que a Nay sabe. */
  const ondeEsta: DestinoParceria = aMao
    ?? (comARayssa ? 'rayssa' : comOTel ? 'tel' : etapaDaParceria(lead as any, m))

  /* O BOTÃO SALVAR (Tel, 30/09): "um botão para salvar e quando eu salvar ele
     vai automaticamente para a etapa lá nas conversas". Escolher só acende o
     botão; nada sai daqui até ele clicar em Salvar -- um clique errado no
     menu não deve mudar a conversa de lugar. */
  const [escolhido, setEscolhido] = useState<DestinoParceria>(ondeEsta)
  useEffect(() => { setEscolhido(ondeEsta); setSalvo(false); setErro(null) }, [lead.id, ondeEsta])
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
    setSalvando(true); setErro(null); setSalvo(false)
    try {
      const r = await fetch(`/api/leads/${lead.id}/contato`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ etapa }),
      })
      if (!r.ok) throw new Error((await r.json().catch(() => ({})))?.error || 'não salvou')
      // a tela não espera o próximo carregamento para mostrar a mudança
      const antes = (lead as any).custom_attributes || {}
      const depois = { ...antes }
      // 'todos' solta a conversa e devolve à Nay; o resto prende
      if (etapa === 'todos') delete depois.etapa_parceria
      else depois.etapa_parceria = etapa
      onUpdateLead?.(lead.id, { custom_attributes: depois } as any)
      setSalvo(true)
    } catch (e: any) {
      setErro(e?.message || 'não salvou')
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
              onClick={() => setEscolhido(d)}
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
        {salvo && !mudou && <span className="text-[11px] text-emerald-500">movido para {ROTULO_DA_ETAPA[ondeEsta]}</span>}
      </div>
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
              ? 'A Nay já sabe. Nada fica preso: se abrir visita, fechamento, ou o imóvel for dele, a conversa vai para a etapa do fato — e esta escolha vale 7 dias.'
              : 'A Nay está decidindo sozinha: visita passada à equipe, dono do imóvel ou checklist pedido.'}
        </p>
      )}
    </div>
  )
}
