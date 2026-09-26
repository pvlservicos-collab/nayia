'use client'

/*
 * Aba "WhatsApp API (captação)" -- o número novo, pela API Oficial da Meta.
 * A tela é a mesma da parceria; o que muda é a LINHA (Tel, 25/09/2026).
 *
 * O `key` não é enfeite: sem ele o React reaproveita a instância do
 * ChatWhatsApp ao trocar de aba (mesmo componente, mesma posição na árvore)
 * e o estado da conversa aberta atravessava de uma linha para a outra.
 */
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'

export default function ChatCaptacaoPage() {
  return <ChatWhatsApp key="captacao" linha="captacao" />
}
