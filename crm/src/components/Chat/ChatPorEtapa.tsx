'use client'

/**
 * VISITA e PROPRIETÁRIOS (v2 do CRM, Pedro, 03/11/2026; lib/versaoDoCrm.ts): uma etapa, os dois números (Leads e Parceria)
 * juntos, com a faixa de qual número a conversa fala. "Se tem conversa de dois números, prioridade é a Parceria": o mesmo
 * telefone nos dois aparece uma vez só, pela Parceria. A tela é a ChatJuntado (a cara do Leads).
 */
import { useCallback, useMemo } from 'react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import ChatJuntado from './ChatJuntado'

export default function ChatPorEtapa({ etapa }: { etapa: 'visita' | 'proprietarios' }) {
  const { leads } = useLeadsContext()
  const { ehProprietario, ehVisita } = usePapelDoContato()
  const daEtapa = useCallback((l: LeadWithOwner) => {
    const linha = getLinhaWhatsapp(l)
    if (linha !== 'captacao' && linha !== 'parceria') return false
    return etapa === 'visita' ? ehVisita(l) : ehProprietario(l)
  }, [etapa, ehVisita, ehProprietario])

  // os telefones que já estão nesta etapa pela Parceria: a conversa do Leads do mesmo telefone não aparece
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria' && daEtapa(l))
    .map((l) => fim8(l.phone)).filter(Boolean)), [leads, daEtapa])
  const pertence = useCallback((l: LeadWithOwner) => daEtapa(l)
    && !(getLinhaWhatsapp(l) === 'captacao' && pelaParceria.has(fim8(l.phone))), [daEtapa, pelaParceria])

  return etapa === 'visita' ? (
    <ChatJuntado titulo="Visita" subtitulo="Quem está na etapa visita, nos dois números · a resposta sai pelo número de cada conversa"
                 pertence={pertence} chaveAbas="crm:abas-visita" vazio="Ninguém na etapa visita agora." />
  ) : (
    <ChatJuntado titulo="Proprietários" subtitulo="Os donos dos dois números, num lugar só · a resposta sai pelo número de cada conversa"
                 pertence={pertence} chaveAbas="crm:abas-proprietarios" vazio="Nenhum proprietário agora." />
  )
}
