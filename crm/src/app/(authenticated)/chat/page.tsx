'use client'

/*
 * Aba "WhatsApp API Oficial" -- o número (92) 8456-0874, pela API Oficial da
 * Meta. A tela é a mesma das outras; o que muda é a LINHA (Tel, 25/09/2026).
 * Até 28/09 esta aba se chamava "captação" e juntava a Z-API da captação; hoje
 * cada número tem a sua (Tel: "São 3 WhatsApp, cada um em uma tab").
 *
 * O `key` não é enfeite: sem ele o React reaproveita a instância do
 * ChatWhatsApp ao trocar de aba (mesmo componente, mesma posição na árvore)
 * e o estado da conversa aberta atravessava de uma linha para a outra.
 */
import ChatWhatsApp from '@/components/Chat/ChatWhatsApp'

export default function ChatOficialPage() {
  return <ChatWhatsApp key="oficial" linha="oficial" />
}
