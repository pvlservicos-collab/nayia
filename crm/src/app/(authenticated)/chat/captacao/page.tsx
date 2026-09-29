'use client'

/*
 * Aba "WhatsApp Captação" -- o número (92) 8595-6408, o WhatsApp da Imob Easy,
 * pela instância da captação na Z-API (Tel, 28/09/2026: "o número de captação,
 * que é o outro, em outra instância da Z-API").
 *
 * Sobre o `key`, ver o comentário em ../page.tsx: ele força o remonte na
 * troca de aba, para nenhuma conversa atravessar de uma linha para a outra.
 */
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'

export default function ChatCaptacaoPage() {
  return <ChatWhatsApp key="captacao" linha="captacao" />
}
