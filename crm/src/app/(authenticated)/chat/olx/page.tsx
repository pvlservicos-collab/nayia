'use client'

/*
 * Aba "Chat OLX" do menu (Pedro, 08/10/2026): o chat da OLX dentro do CRM, uma aba por conta (proprietários e
 * corretores), para receber e responder. Ver src/components/Chat/ChatOlxContas.tsx, src/lib/olxChat.ts e
 * crm/docs/olx/chat-da-olx.md. O que o bot da OLX consultou continua aqui, no botão "Consultas do bot".
 */
import ChatOlxContas from '@/components/Chat/ChatOlxContas'

export default function ChatOlxPage() {
  return (
    <div className="chat-theme h-full flex flex-col min-h-0">
      <ChatOlxContas />
    </div>
  )
}
