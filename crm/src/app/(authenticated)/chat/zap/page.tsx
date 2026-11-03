'use client'

/*
 * Aba "Chat Zap" do menu (Pedro, 03/11/2026: "pessoal do zap ... cria lá um chat Zap no crm"). Os leads do Canal Pro
 * (ZAP Imóveis, Viva Real, OLX) como conversas, os imóveis do XML deles e as informações da integração. A mesma tela do
 * Chat Chaves na Mão (src/components/Chat/ChatChavesNaMao.tsx, portal "zap"; migrações 542/574), no roxo do Chat OLX.
 */
import ChatChavesNaMao from '@/components/Chat/ChatChavesNaMao'

export default function ChatZapPage() {
  return (
    <div className="chat-theme olx-theme h-full flex flex-col min-h-0">
      <ChatChavesNaMao portal="zap" />
    </div>
  )
}
