'use client'

/*
 * ARQUITETURA (Pedro, 03/11/2026: "Arquitetura vem pra dentro do menu Mais"): o fluxograma dos agentes da Nay Leads, que era
 * uma aba ao lado da agenda no WhatsApp Leads (24/10), agora é uma página do "+ Mais". Ver ArquiteturaDosAgentes.tsx.
 */
import ArquiteturaDosAgentes from '@/components/Chat/ArquiteturaDosAgentes'

export default function ArquiteturaPage() {
  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      <ArquiteturaDosAgentes />
    </div>
  )
}
