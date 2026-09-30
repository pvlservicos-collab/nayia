/*
 * QUEM ESPERA RESPOSTA (Pedro, 30/09/2026: "o número de gente que falta
 * responder ainda tá alto sendo que eu já respondi no CRM").
 *
 * Medido em 30/09: das conversas contadas, a última mensagem da pessoa era, em
 * boa parte, "ok", "obrigado", 👍 DEPOIS da resposta nossa -- isso fecha a
 * conversa, não pede resposta. E o próprio número da Nay (Parceria, final
 * 3618) virou lead na linha da captação, com 53 mensagens "sem resposta".
 *
 * "sim" e saudação continuam contando: "sim" depois de "quer visitar?" pede
 * ação, e "bom dia" abre conversa.
 */
// uma ou mais destas, e nada mais: "ok", "ok obrigado", "show valeu"
const CORTESIA = /^(?:(?:ok+|okay|blz|beleza|certo|certinho|show|top|otimo|perfeito|combinado|fechado|joia|obrigad[oa]s?|muito|obg|vlw|valeu|de nada|imagina|entendi|entendido|ta bom|ta certo|tamo junto|abraco|abs)\s?)+$/

/** Os dois números da Nay: Parceria (Z-API) e API oficial. Lead deles é eco, não pessoa. */
const NUMEROS_DA_NAY = ['94453618', '84560874']

export function soCortesia(texto: string | null | undefined): boolean {
  const cru = String(texto || '').trim()
  if (!cru) return false
  if (cru.startsWith('Reagiu com')) return true
  const s = cru.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, ' ').replace(/\s+/g, ' ').trim()
  if (!s) return true                       // só emoji ou pontuação
  return s.length <= 40 && CORTESIA.test(s)
}

export function ehNumeroDaNay(phone: string | null | undefined): boolean {
  return NUMEROS_DA_NAY.includes(String(phone || '').replace(/\D/g, '').slice(-8))
}

/** A última mensagem é da pessoa, pede resposta e não é a própria Nay. */
export function pedeResposta(l: { last_message_sender_type?: string | null; last_message_content?: string | null;
                                  phone?: string | null }): boolean {
  return l.last_message_sender_type === 'lead' && !soCortesia(l.last_message_content) && !ehNumeroDaNay(l.phone)
}
