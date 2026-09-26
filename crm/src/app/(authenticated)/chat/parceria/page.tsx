'use client'

/*
 * Aba "WhatsApp Parceria" -- o número que já está no ar pela Z-API, onde a
 * Nay atende corretor parceiro (Tel, 25/09/2026).
 *
 * Sobre o `key`, ver o comentário em ../page.tsx: ele força o remonte na
 * troca de aba, para nenhuma conversa atravessar de uma linha para a outra.
 */
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'

export default function ChatParceriaPage() {
  return <ChatWhatsApp key="parceria" linha="parceria" />
}
