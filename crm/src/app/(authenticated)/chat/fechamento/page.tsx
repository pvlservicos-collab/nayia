'use client'

/* FECHAMENTO (v2 do CRM, Pedro, 04/11/2026): a última etapa, depois de Proprietários; só o Tel e quem ele incluir na conversa.
   Ver src/components/Chat/ChatPorEtapa.tsx e src/hooks/useFechamentoV2.ts. */
import ChatPorEtapa from '@/components/Chat/ChatPorEtapa'

export default function ChatFechamentoPage() {
  return <ChatPorEtapa etapa="fechamento" />
}
