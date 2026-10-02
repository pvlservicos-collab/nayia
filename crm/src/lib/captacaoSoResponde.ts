/**
 * QUEM SÓ RESPONDE NO WHATSAPP DA CAPTAÇÃO (Pedro, 02/10/2026):
 * "põe um aviso para a Rayssa quando ela abrir o WhatsApp de captação, proíbe
 * ela de começar mensagens por lá".
 *
 * O número da captação é o da campanha com os donos: quem escreve primeiro
 * por ele é a Nay da captação. Uma conversa começada à mão por ali confunde o
 * dono (que recebe duas abordagens) e a contagem da campanha. Quem está nesta
 * lista continua RESPONDENDO quem já escreveu; só não começa conversa.
 *
 * A lista é por primeiro nome, em minúsculas. Sem login de papel próprio para
 * isso, é o jeito direto; muda aqui (ou em NEXT_PUBLIC_CAPTACAO_SO_RESPONDE).
 *
 * Este arquivo é puro (serve à tela e ao servidor). A conferência de verdade,
 * que barra o envio, mora em captacaoSoRespondeServidor.ts.
 */
const NOMES = (process.env.NEXT_PUBLIC_CAPTACAO_SO_RESPONDE || 'rayssa')
  .split(',').map((n) => n.trim().toLowerCase()).filter(Boolean)

export function soRespondeNaCaptacao(nome?: string | null): boolean {
  const n = String(nome || '').trim().toLowerCase()
  return !!n && NOMES.some((x) => n === x || n.startsWith(x + ' '))
}

export const AVISO_DA_CAPTACAO =
  'Este é o WhatsApp da CAPTAÇÃO. Por aqui você só responde quem já escreveu: não comece conversa por este número. ' +
  'Para falar com alguém pela primeira vez, use o WhatsApp da Parceria.'

export const RECUSA_DA_CAPTACAO =
  'Você não pode começar conversa pelo WhatsApp da captação. Use o da Parceria.'
