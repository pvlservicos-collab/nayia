'use client'

/*
 * Aba "Chat Chaves na Mão" do menu (Pedro, 21/10/2026: "no lugar de visitantes ... Chat Chaves na Mão igual o olx mesmas
 * coisas"). Os leads do portal como conversas, os imóveis do XML e as informações da integração. Ver
 * src/components/Chat/ChatChavesNaMao.tsx e as migrações 458/459. Usa o visual do Chat OLX (.olx-theme, globals.css);
 * 31/10: .cnm-theme troca o roxo pelo vermelho do Chaves na Mão.
 */
import ChatChavesNaMao from '@/components/Chat/ChatChavesNaMao'

export default function ChatChavesNaMaoPage() {
  return (
    <div className="chat-theme olx-theme cnm-theme h-full flex flex-col min-h-0">
      <ChatChavesNaMao />
    </div>
  )
}
