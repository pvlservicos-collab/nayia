'use client'

/*
 * Aba "Chat OLX" do menu (Pedro, 08/10/2026): os anúncios que o bot da OLX consultou e a mensagem que
 * saiu para cada anunciante. Ver src/components/Chat/ChatOlx.tsx e /api/olx/abordagens.
 */
import ChatOlx from '@/components/Chat/ChatOlx'

export default function ChatOlxPage() {
  return (
    <div className="chat-theme h-full flex flex-col min-h-0">
      <ChatOlx />
    </div>
  )
}
